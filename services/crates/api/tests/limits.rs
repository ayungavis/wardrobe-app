mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use chrono::Duration;
use sqlx::PgPool;
use tower::ServiceExt;
use wardrobe_api::limit::{Bucket, Caller};
use wardrobe_api::{app_with, limit};

use common::{body_json, session, verifier};

// ------------------------------------------------------------------- fixtures

fn forwarded(chain: &str) -> Request<Body> {
    Request::builder()
        .uri("/health")
        .header("x-forwarded-for", chain)
        .body(Body::empty())
        .expect("request")
}

fn bucket(request: &Request<Body>, trusted_hops: usize) -> Bucket {
    use tower_governor::key_extractor::KeyExtractor;
    Caller::behind(trusted_hops)
        .extract(request)
        .expect("a bucket for every request")
}

// ------------------------------------------------------- the forwarded header

#[test]
fn a_forged_prefix_cannot_escape_its_bucket() {
    let honest = bucket(&forwarded("203.0.113.9, 198.51.100.7"), 1);
    let forged = bucket(&forwarded("1.2.3.4, 203.0.113.9, 198.51.100.7"), 1);
    let forged_again = bucket(&forwarded("9.9.9.9, 203.0.113.9, 198.51.100.7"), 1);

    assert_eq!(
        honest, forged,
        "anything left of the trusted hop is client-supplied; trusting it lets a caller \
         mint a fresh bucket per request and the limit enforces nothing"
    );
    assert_eq!(forged, forged_again);
}

#[test]
fn the_trusted_hop_count_follows_the_topology() {
    let chain = forwarded("203.0.113.9, 198.51.100.7, 192.0.2.1");

    assert_eq!(bucket(&chain, 1), bucket(&forwarded("x, 192.0.2.1"), 1));
    assert_ne!(bucket(&chain, 1), bucket(&chain, 2));
}

#[test]
fn two_real_callers_stay_in_different_buckets() {
    assert_ne!(
        bucket(&forwarded("203.0.113.9"), 1),
        bucket(&forwarded("203.0.113.10"), 1)
    );
}

#[test]
fn a_bearer_token_outranks_the_address() {
    let request = |token: &str| {
        Request::builder()
            .uri("/v1/whoami")
            .header("x-forwarded-for", "203.0.113.9")
            .header("authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .expect("request")
    };

    assert_ne!(
        bucket(&request("one"), 1),
        bucket(&request("two"), 1),
        "two callers behind one carrier NAT must not spend each other's allowance"
    );
    assert_ne!(
        bucket(&request("one"), 1),
        bucket(&forwarded("203.0.113.9"), 1)
    );
}

#[test]
fn an_unattributable_request_still_gets_a_bucket() {
    let bare = Request::builder()
        .uri("/health")
        .body(Body::empty())
        .expect("request");

    assert_eq!(bucket(&bare, 1), Bucket::Unattributable);
}

// ---------------------------------------------------------------- the ceiling

#[sqlx::test(migrations = "../../migrations")]
async fn the_burst_ends_in_a_429_that_says_when_to_retry(pool: PgPool) -> sqlx::Result<()> {
    let router = app_with(pool, verifier(), None, limit::DEFAULT_TRUSTED_HOPS, false);

    let mut refused = None;
    for _ in 0..200 {
        let response = router
            .clone()
            .oneshot(forwarded("203.0.113.9"))
            .await
            .expect("the router is infallible");
        if response.status() == StatusCode::TOO_MANY_REQUESTS {
            refused = Some(response);
            break;
        }
    }

    let response = refused.expect("the burst has to end somewhere");
    assert!(
        response.headers().contains_key("retry-after"),
        "a 429 without Retry-After tells the client to guess"
    );
    let body = body_json(response).await;
    assert_eq!(body["error"]["code"], "too_many_requests");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_caller_running_out_does_not_refuse_another(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let router = app_with(pool, verifier(), None, limit::DEFAULT_TRUSTED_HOPS, false);

    for _ in 0..200 {
        let _ = router
            .clone()
            .oneshot(forwarded("203.0.113.9"))
            .await
            .expect("the router is infallible");
    }

    let mine = router
        .oneshot(
            Request::builder()
                .uri("/v1/whoami")
                .header("x-forwarded-for", "203.0.113.9")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("the router is infallible");
    assert_eq!(mine.status(), StatusCode::OK);
    Ok(())
}

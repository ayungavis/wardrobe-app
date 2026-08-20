use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use chrono::{Duration, Utc};
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;
use wardrobe_api::auth::hash_token;

async fn call(pool: PgPool, request: Request<Body>) -> Response {
    wardrobe_api::app(pool)
        .oneshot(request)
        .await
        .expect("the router is infallible")
}

async fn body_json(response: Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    serde_json::from_slice(&bytes).expect("json body")
}

fn get(path: &str) -> Request<Body> {
    Request::builder()
        .uri(path)
        .body(Body::empty())
        .expect("request")
}

fn get_with_auth(path: &str, header: &str) -> Request<Body> {
    Request::builder()
        .uri(path)
        .header("authorization", header)
        .body(Body::empty())
        .expect("request")
}

async fn session(
    pool: &PgPool,
    expires_in: Duration,
    revoked: bool,
) -> sqlx::Result<(String, Uuid)> {
    let account_id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(account_id)
        .execute(pool)
        .await?;

    let token = format!("token-{}", Uuid::now_v7());
    let session_id = Uuid::now_v7();
    sqlx::query(
        "insert into session (id, account_id, family_id, token_hash, expires_at, revoked_at)
         values ($1, $2, $1, $3, $4, $5)",
    )
    .bind(session_id)
    .bind(account_id)
    .bind(hash_token(&token))
    .bind(Utc::now() + expires_in)
    .bind(revoked.then(Utc::now))
    .execute(pool)
    .await?;

    Ok((token, account_id))
}

// ------------------------------------------------------------------ health

#[sqlx::test(migrations = "../../migrations")]
async fn health_reports_ok_when_the_database_answers(pool: PgPool) {
    let response = call(pool, get("/health")).await;

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(body_json(response).await["status"], "ok");
}

#[sqlx::test(migrations = "../../migrations")]
async fn health_reports_unavailable_when_the_database_is_gone(pool: PgPool) {
    pool.close().await;

    let response = call(pool, get("/health")).await;

    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(body_json(response).await["error"]["code"], "unavailable");
}

// -------------------------------------------------------------------- auth

#[sqlx::test(migrations = "../../migrations")]
async fn a_valid_token_resolves_to_its_account(pool: PgPool) -> sqlx::Result<()> {
    let (token, account_id) = session(&pool, Duration::hours(1), false).await?;

    let resolved = wardrobe_api::auth::resolve(&pool, &token)
        .await
        .expect("database reachable");

    assert_eq!(resolved.map(|s| s.account_id), Some(account_id));
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_expired_token_does_not_resolve(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::hours(-1), false).await?;

    let resolved = wardrobe_api::auth::resolve(&pool, &token)
        .await
        .expect("database reachable");

    assert!(resolved.is_none());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_revoked_token_does_not_resolve(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::hours(1), true).await?;

    let resolved = wardrobe_api::auth::resolve(&pool, &token)
        .await
        .expect("database reachable");

    assert!(resolved.is_none());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unknown_token_does_not_resolve(pool: PgPool) {
    let resolved = wardrobe_api::auth::resolve(&pool, "never-issued")
        .await
        .expect("database reachable");

    assert!(resolved.is_none());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_protected_route_without_a_header_is_unauthenticated(pool: PgPool) {
    let response = call(pool, get("/v1/whoami")).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert_eq!(
        body_json(response).await["error"]["code"],
        "unauthenticated"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_malformed_authorization_header_is_unauthenticated(pool: PgPool) {
    for header in ["", "Bearer", "Bearer   ", "Basic abc", "token abc"] {
        let response = call(pool.clone(), get_with_auth("/v1/whoami", header)).await;
        assert_eq!(
            response.status(),
            StatusCode::UNAUTHORIZED,
            "header {header:?} should not authenticate"
        );
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_protected_route_accepts_a_valid_token(pool: PgPool) -> sqlx::Result<()> {
    let (token, account_id) = session(&pool, Duration::hours(1), false).await?;

    let response = call(
        pool,
        get_with_auth("/v1/whoami", &format!("Bearer {token}")),
    )
    .await;

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        body_json(response).await["accountId"],
        account_id.to_string()
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_bearer_scheme_is_case_insensitive(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::hours(1), false).await?;

    let response = call(
        pool,
        get_with_auth("/v1/whoami", &format!("bearer {token}")),
    )
    .await;

    assert_eq!(response.status(), StatusCode::OK);
    Ok(())
}

// ------------------------------------------------------------------ openapi

#[sqlx::test(migrations = "../../migrations")]
async fn the_openapi_document_is_served(pool: PgPool) {
    let response = call(pool, get("/openapi.json")).await;

    assert_eq!(response.status(), StatusCode::OK);
    let document = body_json(response).await;
    assert_eq!(document["info"]["title"], "Wardrobe API");
    assert!(document["paths"]["/health"].is_object());
}

#[test]
fn the_committed_openapi_file_matches_the_code() {
    let committed = std::fs::read_to_string("../../openapi.json")
        .expect("services/openapi.json is missing — run `make backend-openapi`");
    let generated = wardrobe_api::openapi::document();

    assert_eq!(
        committed.trim(),
        generated.trim(),
        "services/openapi.json is stale — run `make backend-openapi`"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_response_carries_a_request_id(pool: PgPool) -> sqlx::Result<()> {
    let response = call(pool.clone(), get("/health")).await;

    let id = response
        .headers()
        .get("x-request-id")
        .expect("the layer stamps one when the caller sends none");
    assert!(Uuid::parse_str(id.to_str().expect("ascii")).is_ok());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_caller_supplied_request_id_is_propagated(pool: PgPool) -> sqlx::Result<()> {
    let supplied = "0199aa11-2233-7445-8899-aabbccddeeff";
    let request = Request::builder()
        .uri("/health")
        .header("x-request-id", supplied)
        .body(Body::empty())
        .expect("request");

    let response = call(pool.clone(), request).await;

    assert_eq!(
        response.headers().get("x-request-id").unwrap(),
        supplied,
        "a client tracing one call across services must see its own id back"
    );
    Ok(())
}

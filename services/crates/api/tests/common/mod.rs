// One shared module for every test binary, so a helper only two of
// the three use is dead code in the third. Split into per-subject submodules if
// that ever hides a real unused helper.
#![allow(dead_code)]

use axum::body::Body;
use axum::http::Request;
use axum::response::Response;
use chrono::{Duration, Utc};
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;
use wardrobe_api::auth::hash_token;

pub fn verifier() -> std::sync::Arc<wardrobe_api::auth::apple::Verifier> {
    std::sync::Arc::new(wardrobe_api::auth::apple::Verifier::new(None))
}

pub async fn call(pool: PgPool, request: Request<Body>) -> Response {
    wardrobe_api::app(pool, verifier())
        .oneshot(request)
        .await
        .expect("the router is infallible")
}

pub async fn body_json(response: Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body");
    serde_json::from_slice(&bytes).expect("json body")
}

pub fn get(path: &str) -> Request<Body> {
    Request::builder()
        .uri(path)
        .body(Body::empty())
        .expect("request")
}

pub fn get_with_auth(path: &str, header: &str) -> Request<Body> {
    Request::builder()
        .uri(path)
        .header("authorization", header)
        .body(Body::empty())
        .expect("request")
}

pub async fn session(
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

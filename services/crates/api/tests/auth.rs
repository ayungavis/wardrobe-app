mod common;

use axum::http::StatusCode;
use chrono::Duration;
use sqlx::PgPool;

use common::{body_json, call, get, get_with_auth, session};
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

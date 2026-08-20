use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use chrono::{Duration, Utc};
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;
use wardrobe_api::auth::hash_token;

fn verifier() -> std::sync::Arc<wardrobe_api::auth::apple::Verifier> {
    std::sync::Arc::new(wardrobe_api::auth::apple::Verifier::new(None))
}

async fn call(pool: PgPool, request: Request<Body>) -> Response {
    wardrobe_api::app(pool, verifier())
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

fn post(path: &str, body: &Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(path)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .expect("request")
}

async fn start_anonymous(pool: &PgPool, device_id: Uuid) -> Value {
    let response = call(
        pool.clone(),
        post(
            "/v1/sessions/anonymous",
            &serde_json::json!({ "deviceId": device_id }),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    body_json(response).await
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_same_device_always_returns_to_the_same_anonymous_account(
    pool: PgPool,
) -> sqlx::Result<()> {
    let device_id = Uuid::now_v7();

    let first = start_anonymous(&pool, device_id).await;
    let second = start_anonymous(&pool, device_id).await;

    assert_eq!(first["accountId"], second["accountId"]);
    assert_ne!(
        first["accessToken"], second["accessToken"],
        "a fresh session each time, but the same account behind it"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_issued_token_authenticates_the_account_it_names(pool: PgPool) -> sqlx::Result<()> {
    let issued = start_anonymous(&pool, Uuid::now_v7()).await;

    let request = Request::builder()
        .uri("/v1/whoami")
        .header(
            "authorization",
            format!("Bearer {}", issued["accessToken"].as_str().unwrap()),
        )
        .body(Body::empty())
        .expect("request");
    let whoami = body_json(call(pool.clone(), request).await).await;

    assert_eq!(whoami["accountId"], issued["accountId"]);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_the_hash_of_a_token_is_stored(pool: PgPool) -> sqlx::Result<()> {
    let issued = start_anonymous(&pool, Uuid::now_v7()).await;
    let token = issued["accessToken"].as_str().unwrap();

    let (matching,): (i64,) =
        sqlx::query_as("select count(*) from session where encode(token_hash, 'hex') = $1")
            .bind(token)
            .fetch_one(&pool)
            .await?;

    assert_eq!(matching, 0, "the token itself must never be a stored value");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_id_that_is_not_a_uuid_is_a_client_error(pool: PgPool) -> sqlx::Result<()> {
    let response = call(
        pool.clone(),
        post(
            "/v1/sessions/anonymous",
            &serde_json::json!({ "deviceId": "not-a-uuid" }),
        ),
    )
    .await;

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn apple_sign_in_reports_itself_unavailable_when_unconfigured(
    pool: PgPool,
) -> sqlx::Result<()> {
    let response = call(
        pool.clone(),
        post(
            "/v1/sessions/apple",
            &serde_json::json!({
                "deviceId": Uuid::now_v7(),
                "identityToken": "irrelevant",
                "nonce": "irrelevant",
            }),
        ),
    )
    .await;

    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn signing_out_revokes_this_device_and_leaves_the_others_alone(
    pool: PgPool,
) -> sqlx::Result<()> {
    let here = start_anonymous(&pool, Uuid::now_v7()).await;
    let elsewhere = start_anonymous(&pool, Uuid::now_v7()).await;

    let request = Request::builder()
        .method("DELETE")
        .uri("/v1/sessions/current")
        .header(
            "authorization",
            format!("Bearer {}", here["accessToken"].as_str().unwrap()),
        )
        .body(Body::empty())
        .expect("request");
    assert_eq!(
        call(pool.clone(), request).await.status(),
        StatusCode::NO_CONTENT
    );

    assert!(
        wardrobe_api::auth::resolve(&pool, here["accessToken"].as_str().unwrap())
            .await
            .expect("query")
            .is_none()
    );
    assert!(
        wardrobe_api::auth::resolve(&pool, elsewhere["accessToken"].as_str().unwrap())
            .await
            .expect("query")
            .is_some()
    );
    Ok(())
}

async fn account_of(pool: &PgPool, device_id: Uuid) -> Option<Uuid> {
    sqlx::query_scalar("select account_id from account_device where anonymous_id = $1")
        .bind(device_id)
        .fetch_optional(pool)
        .await
        .expect("query")
}

async fn link(pool: &PgPool, subject: &str, device_id: Uuid) -> Result<Uuid, StatusCode> {
    let mut tx = pool.begin().await.expect("transaction");
    let outcome = wardrobe_api::session::link_apple(&mut tx, subject, device_id).await;
    match outcome {
        Ok(account_id) => {
            tx.commit().await.expect("commit");
            Ok(account_id)
        }
        Err(_) => Err(StatusCode::CONFLICT),
    }
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_first_sign_in_adopts_the_anonymous_account_rather_than_moving_its_rows(
    pool: PgPool,
) -> sqlx::Result<()> {
    let device_id = Uuid::now_v7();
    let anonymous = start_anonymous(&pool, device_id).await;
    let anonymous_id = Uuid::parse_str(anonymous["accountId"].as_str().unwrap()).unwrap();

    let linked = link(&pool, "001234.apple.subject", device_id)
        .await
        .unwrap();

    assert_eq!(
        linked, anonymous_id,
        "adopting means the account keeps its identity, so nothing has to be renumbered"
    );
    let (accounts,): (i64,) = sqlx::query_as("select count(*) from account")
        .fetch_one(&pool)
        .await?;
    assert_eq!(accounts, 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_second_empty_device_joins_the_existing_account(pool: PgPool) -> sqlx::Result<()> {
    let first_device = Uuid::now_v7();
    start_anonymous(&pool, first_device).await;
    let account_id = link(&pool, "001234.apple.subject", first_device)
        .await
        .unwrap();

    let second_device = Uuid::now_v7();
    start_anonymous(&pool, second_device).await;
    let joined = link(&pool, "001234.apple.subject", second_device)
        .await
        .unwrap();

    assert_eq!(
        joined, account_id,
        "cross-device restore lands on one account"
    );
    assert_eq!(account_of(&pool, second_device).await, Some(account_id));
    let (accounts,): (i64,) = sqlx::query_as("select count(*) from account")
        .fetch_one(&pool)
        .await?;
    assert_eq!(
        accounts, 1,
        "the emptied anonymous account is not left behind"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_second_device_holding_data_is_a_conflict_and_neither_side_is_touched(
    pool: PgPool,
) -> sqlx::Result<()> {
    let first_device = Uuid::now_v7();
    start_anonymous(&pool, first_device).await;
    let account_id = link(&pool, "001234.apple.subject", first_device)
        .await
        .unwrap();

    let second_device = Uuid::now_v7();
    let local = start_anonymous(&pool, second_device).await;
    let local_id = Uuid::parse_str(local["accountId"].as_str().unwrap()).unwrap();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq) values ($1, $2, 'top', 1)",
    )
    .bind(Uuid::now_v7())
    .bind(local_id)
    .execute(&pool)
    .await?;

    assert_eq!(
        link(&pool, "001234.apple.subject", second_device).await,
        Err(StatusCode::CONFLICT)
    );

    assert_eq!(account_of(&pool, second_device).await, Some(local_id));
    let (accounts,): (i64,) = sqlx::query_as("select count(*) from account")
        .fetch_one(&pool)
        .await?;
    assert_eq!(accounts, 2, "both accounts survive an unresolved link");
    assert_ne!(local_id, account_id);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn signing_in_on_a_device_that_never_used_the_app_creates_the_account(
    pool: PgPool,
) -> sqlx::Result<()> {
    let device_id = Uuid::now_v7();

    let account_id = link(&pool, "001234.apple.subject", device_id)
        .await
        .unwrap();

    assert_eq!(account_of(&pool, device_id).await, Some(account_id));
    let subject: Option<String> =
        sqlx::query_scalar("select apple_subject from account where id = $1")
            .bind(account_id)
            .fetch_one(&pool)
            .await?;
    assert_eq!(subject.as_deref(), Some("001234.apple.subject"));
    Ok(())
}

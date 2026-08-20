mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call};

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
    let outcome = wardrobe_api::account::link_apple(&mut tx, subject, device_id).await;
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

async fn refresh(pool: &PgPool, token: &str) -> Response {
    call(
        pool.clone(),
        post(
            "/v1/sessions/refresh",
            &serde_json::json!({ "refreshToken": token }),
        ),
    )
    .await
}

async fn is_live(pool: &PgPool, access_token: &str) -> bool {
    wardrobe_api::auth::resolve(pool, access_token)
        .await
        .expect("query")
        .is_some()
}

#[sqlx::test(migrations = "../../migrations")]
async fn rotating_issues_a_new_pair_and_retires_the_old_one(pool: PgPool) -> sqlx::Result<()> {
    let first = start_anonymous(&pool, Uuid::now_v7()).await;

    let response = refresh(&pool, first["refreshToken"].as_str().unwrap()).await;
    assert_eq!(response.status(), StatusCode::OK);
    let second = body_json(response).await;

    assert_eq!(second["accountId"], first["accountId"]);
    assert_ne!(second["accessToken"], first["accessToken"]);
    assert_ne!(second["refreshToken"], first["refreshToken"]);
    assert!(is_live(&pool, second["accessToken"].as_str().unwrap()).await);
    assert!(
        !is_live(&pool, first["accessToken"].as_str().unwrap()).await,
        "a 30-day access token that outlived its rotation would make rotation cosmetic"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_rotation_stays_inside_one_family(pool: PgPool) -> sqlx::Result<()> {
    let first = start_anonymous(&pool, Uuid::now_v7()).await;
    let second = body_json(refresh(&pool, first["refreshToken"].as_str().unwrap()).await).await;

    let families: Vec<Uuid> =
        sqlx::query_scalar("select distinct family_id from session where account_id = $1")
            .bind(Uuid::parse_str(second["accountId"].as_str().unwrap()).unwrap())
            .fetch_all(&pool)
            .await?;

    assert_eq!(
        families.len(),
        1,
        "rotation continues a family, it does not start one"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn replaying_a_rotated_refresh_token_revokes_the_whole_family(
    pool: PgPool,
) -> sqlx::Result<()> {
    let first = start_anonymous(&pool, Uuid::now_v7()).await;
    let stolen = first["refreshToken"].as_str().unwrap().to_owned();
    let second = body_json(refresh(&pool, &stolen).await).await;

    let replay = refresh(&pool, &stolen).await;

    assert_eq!(replay.status(), StatusCode::UNAUTHORIZED);
    assert!(
        !is_live(&pool, second["accessToken"].as_str().unwrap()).await,
        "the thief and the victim lose the same session, which is what makes theft visible"
    );
    let (live,): (i64,) =
        sqlx::query_as("select count(*) from session where account_id = $1 and revoked_at is null")
            .bind(Uuid::parse_str(first["accountId"].as_str().unwrap()).unwrap())
            .fetch_one(&pool)
            .await?;
    assert_eq!(live, 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_families_theft_does_not_touch_another_device(pool: PgPool) -> sqlx::Result<()> {
    let here = start_anonymous(&pool, Uuid::now_v7()).await;
    let elsewhere = start_anonymous(&pool, Uuid::now_v7()).await;
    let stolen = here["refreshToken"].as_str().unwrap().to_owned();
    refresh(&pool, &stolen).await;

    refresh(&pool, &stolen).await;

    assert!(is_live(&pool, elsewhere["accessToken"].as_str().unwrap()).await);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unknown_refresh_token_reveals_nothing_and_revokes_nothing(
    pool: PgPool,
) -> sqlx::Result<()> {
    let live = start_anonymous(&pool, Uuid::now_v7()).await;

    let response = refresh(&pool, &wardrobe_api::session::secret()).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    let body = body_json(response).await;
    assert_eq!(body["error"]["code"], "unauthenticated");
    assert!(is_live(&pool, live["accessToken"].as_str().unwrap()).await);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_signed_out_family_cannot_be_refreshed_back_to_life(pool: PgPool) -> sqlx::Result<()> {
    let issued = start_anonymous(&pool, Uuid::now_v7()).await;
    let request = Request::builder()
        .method("DELETE")
        .uri("/v1/sessions/current")
        .header(
            "authorization",
            format!("Bearer {}", issued["accessToken"].as_str().unwrap()),
        )
        .body(Body::empty())
        .expect("request");
    call(pool.clone(), request).await;

    let response = refresh(&pool, issued["refreshToken"].as_str().unwrap()).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_expired_refresh_token_is_refused(pool: PgPool) -> sqlx::Result<()> {
    let issued = start_anonymous(&pool, Uuid::now_v7()).await;
    sqlx::query("update session set refresh_expires_at = now() - interval '1 day'")
        .execute(&pool)
        .await?;

    let response = refresh(&pool, issued["refreshToken"].as_str().unwrap()).await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    Ok(())
}

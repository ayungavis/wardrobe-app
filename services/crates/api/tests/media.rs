mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use chrono::Duration;
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

use common::{
    body_json, call, call_with, call_without_storage, get_with_auth, session, storage_in,
};

// ------------------------------------------------------------------- fixtures

fn reserve(token: &str, body: &Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/v1/media")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(body.to_string()))
        .expect("request")
}

fn original(media_id: Uuid) -> Value {
    json!({
        "mediaId": media_id,
        "kind": "original",
        "contentType": "image/jpeg",
        "byteSize": 12
    })
}

async fn download(pool: &PgPool, token: &str, media_id: Uuid) -> Response {
    call(
        pool.clone(),
        get_with_auth(&format!("/v1/media/{media_id}"), &format!("Bearer {token}")),
    )
    .await
}

async fn uploaded_at(pool: &PgPool, media_id: Uuid) -> Option<chrono::DateTime<chrono::Utc>> {
    sqlx::query_scalar("select uploaded_at from media_object where id = $1")
        .bind(media_id)
        .fetch_one(pool)
        .await
        .expect("query")
}

// ------------------------------------------------------------------ reserving

#[sqlx::test(migrations = "../../migrations")]
async fn reserving_returns_an_upload_url_and_records_the_object(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let media_id = Uuid::now_v7();

    let response = call(pool.clone(), reserve(&token, &original(media_id))).await;
    assert_eq!(response.status(), StatusCode::OK);
    let granted = body_json(response).await;
    assert_eq!(granted["mediaId"], media_id.to_string());
    assert!(granted["url"].as_str().expect("a url").starts_with("http"));

    let owner: Uuid = sqlx::query_scalar("select account_id from media_object where id = $1")
        .bind(media_id)
        .fetch_one(&pool)
        .await?;
    assert_eq!(owner, account);
    assert!(
        uploaded_at(&pool, media_id).await.is_none(),
        "a url is a grant to upload, not proof that anything did"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn reserving_the_same_id_twice_makes_one_object(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let media_id = Uuid::now_v7();

    call(pool.clone(), reserve(&token, &original(media_id))).await;
    let response = call(pool.clone(), reserve(&token, &original(media_id))).await;
    assert_eq!(response.status(), StatusCode::OK);

    let rows: i64 = sqlx::query_scalar("select count(*) from media_object where id = $1")
        .bind(media_id)
        .fetch_one(&pool)
        .await?;
    assert_eq!(rows, 1, "a retry must not mint a second object");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unknown_kind_is_a_client_error(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let body = json!({
        "mediaId": Uuid::now_v7(), "kind": "something-else", "contentType": "image/jpeg"
    });

    let response = call(pool.clone(), reserve(&token, &body)).await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn claiming_an_id_another_account_owns_is_a_conflict(pool: PgPool) -> sqlx::Result<()> {
    let (mine, _) = session(&pool, Duration::days(1), false).await?;
    let (theirs, _) = session(&pool, Duration::days(1), false).await?;
    let media_id = Uuid::now_v7();

    call(pool.clone(), reserve(&theirs, &original(media_id))).await;
    let response = call(pool.clone(), reserve(&mine, &original(media_id))).await;

    assert_eq!(response.status(), StatusCode::CONFLICT);
    Ok(())
}

// ---------------------------------------------------------------- downloading

#[sqlx::test(migrations = "../../migrations")]
async fn downloading_before_the_bytes_arrive_is_not_found(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let media_id = Uuid::now_v7();
    call(pool.clone(), reserve(&token, &original(media_id))).await;

    let response = download(&pool, &token, media_id).await;
    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "handing out a url that points at nothing is worse than saying so"
    );
    assert!(uploaded_at(&pool, media_id).await.is_none());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn downloading_after_a_real_upload_stamps_when_it_arrived(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let media_id = Uuid::now_v7();

    let granted = body_json(call(pool.clone(), reserve(&token, &original(media_id))).await).await;
    reqwest::Client::new()
        .put(granted["url"].as_str().expect("a url"))
        .header("content-type", "image/jpeg")
        .body("twelve bytes")
        .send()
        .await
        .expect("the signed url is reachable")
        .error_for_status()
        .expect("the signature is accepted");

    let response = download(&pool, &token, media_id).await;
    assert_eq!(response.status(), StatusCode::OK);
    let ready = body_json(response).await;
    assert_eq!(ready["byteSize"], 12);
    assert!(
        uploaded_at(&pool, media_id).await.is_some(),
        "the first successful download is when the server learns the bytes landed"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_accounts_media_reveals_nothing(pool: PgPool) -> sqlx::Result<()> {
    let (mine, _) = session(&pool, Duration::days(1), false).await?;
    let (theirs, _) = session(&pool, Duration::days(1), false).await?;
    let media_id = Uuid::now_v7();
    call(pool.clone(), reserve(&theirs, &original(media_id))).await;

    let response = download(&pool, &mine, media_id).await;
    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "conflict would confirm the id exists somewhere, which is not this caller's business"
    );
    Ok(())
}

// ------------------------------------------------------------ when it is off

#[sqlx::test(migrations = "../../migrations")]
async fn without_storage_configured_media_reports_itself_unavailable(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;

    let response =
        call_without_storage(pool.clone(), reserve(&token, &original(Uuid::now_v7()))).await;

    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(body_json(response).await["error"]["code"], "unavailable");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn media_without_a_token_is_unauthenticated(pool: PgPool) {
    let response = call(
        pool,
        Request::builder()
            .method("POST")
            .uri("/v1/media")
            .header("content-type", "application/json")
            .body(Body::from(original(Uuid::now_v7()).to_string()))
            .expect("request"),
    )
    .await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_stamped_object_is_served_without_asking_the_store_again(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let media_id = Uuid::now_v7();

    let granted = body_json(call(pool.clone(), reserve(&token, &original(media_id))).await).await;
    reqwest::Client::new()
        .put(granted["url"].as_str().expect("a url"))
        .header("content-type", "image/jpeg")
        .body("twelve bytes")
        .send()
        .await
        .expect("reachable")
        .error_for_status()
        .expect("accepted");
    assert_eq!(
        download(&pool, &token, media_id).await.status(),
        StatusCode::OK
    );

    let blind = call_with(
        pool.clone(),
        get_with_auth(&format!("/v1/media/{media_id}"), &format!("Bearer {token}")),
        Some(storage_in("a-bucket-that-does-not-exist")),
    )
    .await;

    assert_eq!(
        blind.status(),
        StatusCode::OK,
        "once the size is stored, asking the store again is a round trip on every image the app shows"
    );
    assert_eq!(body_json(blind).await["byteSize"], 12);
    Ok(())
}

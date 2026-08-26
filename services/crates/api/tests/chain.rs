mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call, storage};

// ------------------------------------------------------------------- fixtures

fn post(path: &str, token: Option<&str>, body: &Value) -> Request<Body> {
    let mut builder = Request::builder()
        .method("POST")
        .uri(path)
        .header("content-type", "application/json");
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    builder.body(Body::from(body.to_string())).expect("request")
}

fn authed(method: &str, path: &str, token: &str) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(path)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .expect("request")
}

async fn json_ok(pool: &PgPool, request: Request<Body>, what: &str) -> Value {
    let response = call(pool.clone(), request).await;
    assert_eq!(response.status(), StatusCode::OK, "{what}");
    body_json(response).await
}

/// Uploads real bytes through a signed URL and returns the media id.
async fn upload(pool: &PgPool, token: &str, kind: &str, bytes: &'static str) -> Uuid {
    let media_id = Uuid::now_v7();
    let granted = json_ok(
        pool,
        post(
            "/v1/media",
            Some(token),
            &json!({ "mediaId": media_id, "kind": kind, "contentType": "image/jpeg" }),
        ),
        "reserving media",
    )
    .await;

    reqwest::Client::new()
        .put(granted["url"].as_str().expect("an upload url"))
        .header("content-type", "image/jpeg")
        .body(bytes)
        .send()
        .await
        .expect("the signed url is reachable")
        .error_for_status()
        .expect("the signature is accepted");

    media_id
}

// ------------------------------------------------------------------ the chain

async fn seed_curated_card(pool: &PgPool) -> sqlx::Result<Uuid> {
    let card = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_card (id, source, prompt_text, locale)
         values ($1, 'curated', 'Wear something blue', 'en')",
    )
    .bind(card)
    .execute(pool)
    .await?;
    Ok(card)
}

async fn start_a_session_from_nothing_but_a_keychain_uuid(pool: &PgPool) -> (String, Uuid) {
    let issued = json_ok(
        pool,
        post(
            "/v1/sessions/anonymous",
            None,
            &json!({ "deviceId": Uuid::now_v7() }),
        ),
        "starting an anonymous session",
    )
    .await;

    (
        issued["accessToken"].as_str().expect("a token").to_owned(),
        Uuid::parse_str(issued["accountId"].as_str().expect("an account")).expect("uuid"),
    )
}

async fn send_three_objects_straight_to_storage(pool: &PgPool, token: &str) -> (Uuid, Uuid, Uuid) {
    (
        upload(pool, token, "original", "the original frame").await,
        upload(pool, token, "derivative", "the edited frame").await,
        upload(pool, token, "document", "the canvas document").await,
    )
}

async fn complete_one_challenge_referencing_them(
    pool: &PgPool,
    token: &str,
    card: Uuid,
    media: (Uuid, Uuid, Uuid),
) {
    let (photo_media, derivative_media, document_media) = media;
    let photo = Uuid::now_v7();
    let results = json_ok(
        pool,
        post(
            "/v1/sync",
            Some(token),
            &json!({ "mutations": [{
                "id": Uuid::now_v7(),
                "name": "completeChallenge",
                "args": {
                    "completionId": Uuid::now_v7(),
                    "cardId": card,
                    "localDate": "2026-08-21",
                    "timeZone": "Asia/Jakarta",
                    "completedAt": "2026-08-21T10:00:00Z",
                    "photo": { "id": photo, "mediaObjectId": photo_media, "source": "capture" },
                    "derivative": { "id": Uuid::now_v7(), "mediaObjectId": derivative_media },
                    "document": {
                        "id": Uuid::now_v7(), "schemaVersion": 1, "mediaObjectId": document_media
                    },
                    "items": [{
                        "id": Uuid::now_v7(), "wearId": Uuid::now_v7(),
                        "category": "top", "name": "Blue shirt", "sourcePhotoId": photo
                    }]
                }
            }]}),
        ),
        "completing the challenge",
    )
    .await;

    assert_eq!(results["results"][0]["status"], "applied");
    assert_eq!(results["results"][0]["record"]["status"], "canonical");
}

async fn pull_the_feed_from_zero_and_find_every_artefact(pool: &PgPool, token: &str) {
    let feed = json_ok(
        pool,
        authed("GET", "/v1/changes?since=0", token),
        "pulling the feed",
    )
    .await;
    let kinds: Vec<&str> = feed["changes"]
        .as_array()
        .expect("changes")
        .iter()
        .map(|change| change["kind"].as_str().expect("kind"))
        .collect();

    for kind in [
        "photo",
        "photoDerivative",
        "challengeCompletion",
        "canvasDocument",
        "wardrobeItem",
        "wearRecord",
    ] {
        assert!(kinds.contains(&kind), "the feed dropped {kind}: {kinds:?}");
    }
}

async fn fetch_the_bytes_back_through_a_signed_url(pool: &PgPool, token: &str, media: Uuid) {
    let ready = json_ok(
        pool,
        authed("GET", &format!("/v1/media/{media}"), token),
        "asking for a download url",
    )
    .await;

    let fetched = reqwest::get(ready["url"].as_str().expect("a download url"))
        .await
        .expect("reachable")
        .error_for_status()
        .expect("the signature is accepted")
        .text()
        .await
        .expect("body");

    assert_eq!(fetched, "the original frame");
}

async fn delete_the_account_and_leave_nothing_behind(
    pool: &PgPool,
    token: &str,
    account: Uuid,
) -> sqlx::Result<()> {
    let keys: Vec<String> =
        sqlx::query_scalar("select storage_key from media_object where account_id = $1")
            .bind(account)
            .fetch_all(pool)
            .await?;
    assert_eq!(keys.len(), 3);

    let goodbye = call(pool.clone(), authed("DELETE", "/v1/users/me", token)).await;
    assert_eq!(goodbye.status(), StatusCode::NO_CONTENT);

    let left: i64 = sqlx::query_scalar("select count(*) from account where id = $1")
        .bind(account)
        .fetch_one(pool)
        .await?;
    assert_eq!(left, 0);

    for key in keys {
        assert_eq!(
            storage().await.head(&key).await.expect("head"),
            None,
            "an object outliving the account it belonged to is the failure FR-071 names"
        );
    }
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_whole_loop_works_without_an_ios_client(pool: PgPool) -> sqlx::Result<()> {
    let card = seed_curated_card(&pool).await?;
    let (token, account) = start_a_session_from_nothing_but_a_keychain_uuid(&pool).await;

    let media = send_three_objects_straight_to_storage(&pool, &token).await;
    complete_one_challenge_referencing_them(&pool, &token, card, media).await;

    pull_the_feed_from_zero_and_find_every_artefact(&pool, &token).await;
    fetch_the_bytes_back_through_a_signed_url(&pool, &token, media.0).await;

    delete_the_account_and_leave_nothing_behind(&pool, &token, account).await
}

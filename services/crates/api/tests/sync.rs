mod common;

use std::sync::{Arc, Mutex, OnceLock};

use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::response::Response;
use chrono::Duration;
use serde_json::{Value, json};
use sqlx::PgPool;
use tracing::field::{Field, Visit};
use tracing::span::Attributes;
use tracing_subscriber::layer::{Context, Layer};
use tracing_subscriber::prelude::*;
use uuid::Uuid;

use common::{body_json, call, session};

// ------------------------------------------------------------------- fixtures

fn post(token: &str, body: &Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri("/v1/sync")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(body.to_string()))
        .expect("request")
}

fn batch(mutations: &[Value]) -> Value {
    json!({ "mutations": mutations })
}

fn delete_item(id: Uuid) -> Value {
    json!({ "id": Uuid::now_v7(), "name": "deleteItem", "args": { "id": id } })
}

fn upsert_preferences(args: &Value) -> Value {
    json!({ "id": Uuid::now_v7(), "name": "upsertPreferences", "args": args })
}

async fn item(pool: &PgPool, account_id: Uuid) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq)
         values ($1, $2, 'top', 0)",
    )
    .bind(id)
    .bind(account_id)
    .execute(pool)
    .await?;
    Ok(id)
}

async fn sync(pool: &PgPool, token: &str, body: &Value) -> Value {
    let response = call(pool.clone(), post(token, body)).await;
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "the batch itself is fine"
    );
    body_json(response).await
}

async fn change_seq(pool: &PgPool, account_id: Uuid) -> i64 {
    sqlx::query_scalar("select change_seq from account where id = $1")
        .bind(account_id)
        .fetch_one(pool)
        .await
        .expect("query")
}

async fn refused(pool: &PgPool, token: &str, body: &Value) -> Response {
    call(pool.clone(), post(token, body)).await
}

// --------------------------------------------------------------- replay safety

#[sqlx::test(migrations = "../../migrations")]
async fn replaying_a_batch_changes_nothing_and_does_not_advance_the_cursor(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, account_id) = session(&pool, Duration::days(1), false).await?;
    let item_id = item(&pool, account_id).await?;
    let body = batch(&[delete_item(item_id)]);

    let first = sync(&pool, &token, &body).await;
    assert_eq!(first["results"][0]["status"], "applied");
    let after_first = change_seq(&pool, account_id).await;

    let again = sync(&pool, &token, &body).await;
    assert_eq!(
        again["results"][0]["record"], first["results"][0]["record"],
        "a repeated mutation returns the record it already wrote"
    );
    assert_eq!(
        change_seq(&pool, account_id).await,
        after_first,
        "a replay must not allocate a change position, or every retry would grow the feed"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn each_written_row_takes_its_own_change_position(pool: PgPool) -> sqlx::Result<()> {
    let (token, account_id) = session(&pool, Duration::days(1), false).await?;
    let one = item(&pool, account_id).await?;
    let two = item(&pool, account_id).await?;

    let result = sync(&pool, &token, &batch(&[delete_item(one), delete_item(two)])).await;

    let first = result["results"][0]["record"]["changeSeq"]
        .as_i64()
        .expect("a change position");
    let second = result["results"][1]["record"]["changeSeq"]
        .as_i64()
        .expect("a change position");
    assert_ne!(
        first, second,
        "rows sharing a position let a page boundary hide one of them from the cursor"
    );
    Ok(())
}

// ------------------------------------------------------------------- isolation

#[sqlx::test(migrations = "../../migrations")]
async fn one_failing_mutation_leaves_its_neighbours_applied(pool: PgPool) -> sqlx::Result<()> {
    let (token, account_id) = session(&pool, Duration::days(1), false).await?;

    let result = sync(
        &pool,
        &token,
        &batch(&[
            delete_item(Uuid::now_v7()),
            upsert_preferences(&json!({ "recentStickerIds": ["star"] })),
        ]),
    )
    .await;

    assert_eq!(result["results"][0]["status"], "failed");
    assert_eq!(result["results"][0]["error"]["code"], "not_found");
    assert_eq!(result["results"][1]["status"], "applied");

    let saved: Vec<String> = sqlx::query_scalar(
        "select recent_sticker_ids from account_preference where account_id = $1",
    )
    .bind(account_id)
    .fetch_one(&pool)
    .await?;
    assert_eq!(saved, vec!["star".to_owned()]);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unknown_mutation_name_fails_alone(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;

    let result = sync(
        &pool,
        &token,
        &batch(&[
            json!({ "id": Uuid::now_v7(), "name": "somethingNewerClientsSend", "args": {} }),
            upsert_preferences(&json!({})),
        ]),
    )
    .await;

    assert_eq!(result["results"][0]["status"], "failed");
    assert_eq!(result["results"][0]["error"]["code"], "bad_request");
    assert_eq!(result["results"][1]["status"], "applied");
    Ok(())
}

// --------------------------------------------------------------- authorization

#[sqlx::test(migrations = "../../migrations")]
async fn deleting_another_accounts_item_reports_nothing_and_touches_nothing(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (mine, _) = session(&pool, Duration::days(1), false).await?;
    let (_, theirs) = session(&pool, Duration::days(1), false).await?;
    let their_item = item(&pool, theirs).await?;

    let result = sync(&pool, &mine, &batch(&[delete_item(their_item)])).await;
    assert_eq!(result["results"][0]["error"]["code"], "not_found");

    let still_live: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("select deleted_at from wardrobe_item where id = $1")
            .bind(their_item)
            .fetch_one(&pool)
            .await?;
    assert!(
        still_live.is_none(),
        "another account's row must be untouched"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn sync_without_a_token_is_unauthenticated(pool: PgPool) {
    let response = call(
        pool,
        Request::builder()
            .method("POST")
            .uri("/v1/sync")
            .header("content-type", "application/json")
            .body(Body::from(batch(&[]).to_string()))
            .expect("request"),
    )
    .await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// -------------------------------------------------------------------- the caps

#[sqlx::test(migrations = "../../migrations")]
async fn a_batch_past_the_mutation_cap_is_refused_in_our_own_envelope(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let too_many: Vec<Value> = (0..101).map(|_| upsert_preferences(&json!({}))).collect();

    let response = refused(&pool, &token, &batch(&too_many)).await;
    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(
        body_json(response).await["error"]["code"],
        "payload_too_large"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_body_past_our_own_cap_is_refused_in_our_own_envelope(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let padding = "x".repeat(1_100_000);
    let body = batch(&[upsert_preferences(&json!({ "pad": padding }))]);

    let response = refused(&pool, &token, &body).await;
    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(
        body_json(response).await["error"]["code"],
        "payload_too_large"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_body_axum_itself_rejects_still_arrives_in_our_own_envelope(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let padding = "x".repeat(3_000_000);
    let body = batch(&[upsert_preferences(&json!({ "pad": padding }))]);

    let response = refused(&pool, &token, &body).await;
    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(
        body_json(response).await["error"]["code"],
        "payload_too_large",
        "axum's own rejection is plain text, which the one-envelope rule forbids"
    );
    Ok(())
}

// ----------------------------------------------------------------- preferences

#[sqlx::test(migrations = "../../migrations")]
async fn a_later_mutation_keeps_the_fields_it_does_not_mention(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;

    sync(
        &pool,
        &token,
        &batch(&[upsert_preferences(
            &json!({ "onboardingCompletedAt": "2026-08-20T10:00:00Z" }),
        )]),
    )
    .await;
    let result = sync(
        &pool,
        &token,
        &batch(&[upsert_preferences(
            &json!({ "recentStickerIds": ["heart"] }),
        )]),
    )
    .await;

    let record = &result["results"][0]["record"];
    assert_eq!(record["recentStickerIds"][0], "heart");
    assert!(
        !record["onboardingCompletedAt"].is_null(),
        "naming one field must not clear the others"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_sticker_list_past_the_limit_is_a_client_error_not_an_internal_one(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let thirteen: Vec<String> = (0..13).map(|n| format!("sticker-{n}")).collect();

    let result = sync(
        &pool,
        &token,
        &batch(&[upsert_preferences(&json!({ "recentStickerIds": thirteen }))]),
    )
    .await;

    assert_eq!(
        result["results"][0]["error"]["code"], "bad_request",
        "a database CHECK reaching the client as `internal` tells it to retry forever"
    );
    Ok(())
}

// -------------------------------------------------------------------- tracing

static SEEN: OnceLock<Arc<Mutex<Vec<String>>>> = OnceLock::new();

struct SpanNames(Arc<Mutex<Vec<String>>>);

struct FirstName(Option<String>);

impl Visit for FirstName {
    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "name" {
            self.0 = Some(value.to_owned());
        }
    }

    fn record_debug(&mut self, _field: &Field, _value: &dyn std::fmt::Debug) {}
}

impl<S: tracing::Subscriber> Layer<S> for SpanNames {
    fn on_new_span(&self, attrs: &Attributes<'_>, _id: &tracing::Id, _ctx: Context<'_, S>) {
        if attrs.metadata().name() != "mutation" {
            return;
        }
        let mut visitor = FirstName(None);
        attrs.record(&mut visitor);
        if let Some(name) = visitor.0 {
            self.0.lock().expect("an unpoisoned lock").push(name);
        }
    }
}

fn seen() -> &'static Arc<Mutex<Vec<String>>> {
    SEEN.get_or_init(|| {
        let names = Arc::new(Mutex::new(Vec::new()));
        let _ = tracing_subscriber::registry()
            .with(SpanNames(Arc::clone(&names)))
            .try_init();
        names
    })
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_mutation_span_carries_the_mutation_name(pool: PgPool) -> sqlx::Result<()> {
    let collected = seen();
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let probe = "aNameOnlyThisTestSends";

    sync(
        &pool,
        &token,
        &batch(&[json!({ "id": Uuid::now_v7(), "name": probe, "args": {} })]),
    )
    .await;

    let names = collected.lock().expect("an unpoisoned lock");
    assert!(
        names.iter().any(|name| name == probe),
        "without the name in the span every write in the system looks like one POST /v1/sync"
    );
    Ok(())
}

// ------------------------------------------------------------------ the cursor

#[sqlx::test(migrations = "../../migrations")]
async fn a_write_never_lets_this_device_skip_another_devices_changes(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, account_id) = session(&pool, Duration::days(1), false).await?;
    let item_id = item(&pool, account_id).await?;

    sync(
        &pool,
        &token,
        &batch(&[upsert_preferences(&json!({ "recentStickerIds": ["star"] }))]),
    )
    .await;

    let mine = sync(&pool, &token, &batch(&[delete_item(item_id)])).await;
    assert!(
        mine.get("nextSince").is_none(),
        "a write response is not a cursor: it knows nothing about positions this device never pulled"
    );

    let response = call(
        pool.clone(),
        Request::builder()
            .uri("/v1/changes?since=0")
            .header("authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .expect("request"),
    )
    .await;
    let feed = body_json(response).await;
    let kinds: Vec<&str> = feed["changes"]
        .as_array()
        .expect("changes")
        .iter()
        .map(|change| change["kind"].as_str().expect("a kind"))
        .collect();

    assert!(
        kinds.contains(&"accountPreference"),
        "storing a write response as the cursor skips every position this device never pulled"
    );
    Ok(())
}

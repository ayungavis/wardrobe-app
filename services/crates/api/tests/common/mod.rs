// ponytail: one shared module for every test binary, so a helper only two of
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
    wardrobe_api::app(pool, verifier(), Some(storage()))
        .oneshot(request)
        .await
        .expect("the router is infallible")
}

pub fn storage() -> std::sync::Arc<wardrobe_storage::Storage> {
    std::sync::Arc::new(wardrobe_storage::Storage::new(&settings()))
}

fn settings() -> wardrobe_storage::Settings {
    wardrobe_storage::Settings {
        endpoint: env("S3_ENDPOINT", "http://localhost:9100"),
        region: env("S3_REGION", "us-east-1"),
        bucket: env("S3_BUCKET", "wardrobe"),
        access_key_id: env("S3_ACCESS_KEY_ID", "wardrobe"),
        secret_access_key: env("S3_SECRET_ACCESS_KEY", "wardrobe-dev-secret"),
        path_style: true,
        presign_ttl: std::time::Duration::from_secs(300),
    }
}

fn env(name: &str, fallback: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| fallback.to_owned())
}

pub fn storage_in(bucket: &str) -> std::sync::Arc<wardrobe_storage::Storage> {
    let mut settings = settings();
    bucket.clone_into(&mut settings.bucket);
    std::sync::Arc::new(wardrobe_storage::Storage::new(&settings))
}

pub async fn call_with(
    pool: PgPool,
    request: Request<Body>,
    storage: Option<std::sync::Arc<wardrobe_storage::Storage>>,
) -> Response {
    wardrobe_api::app(pool, verifier(), storage)
        .oneshot(request)
        .await
        .expect("the router is infallible")
}

pub async fn call_without_storage(pool: PgPool, request: Request<Body>) -> Response {
    call_with(pool, request, None).await
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

// ------------------------------------------------------------ captured events

static EVENTS: std::sync::OnceLock<std::sync::Arc<std::sync::Mutex<Vec<String>>>> =
    std::sync::OnceLock::new();

struct Capture(std::sync::Arc<std::sync::Mutex<Vec<String>>>);

struct Fields<'a>(&'a mut String);

impl tracing::field::Visit for Fields<'_> {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        use std::fmt::Write;
        let _ = write!(self.0, "{}={value:?} ", field.name());
    }
}

impl<S: tracing::Subscriber> tracing_subscriber::layer::Layer<S> for Capture {
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
        let mut line = String::new();
        event.record(&mut Fields(&mut line));
        self.0.lock().expect("an unpoisoned lock").push(line);
    }
}

pub fn events() -> &'static std::sync::Arc<std::sync::Mutex<Vec<String>>> {
    EVENTS.get_or_init(|| {
        use tracing_subscriber::prelude::*;
        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let _ = tracing_subscriber::registry()
            .with(Capture(std::sync::Arc::clone(&seen)))
            .try_init();
        seen
    })
}

pub fn recorded(needle: &str) -> bool {
    events()
        .lock()
        .expect("an unpoisoned lock")
        .iter()
        .any(|line| line.contains(needle))
}

// ------------------------------------------------------- one row of every kind

pub struct Seeded {
    pub item: Uuid,
    pub completion: Uuid,
    pub challenge: Uuid,
}

pub struct Base {
    pub media: Uuid,
    pub card: Uuid,
    pub item: Uuid,
    pub photo: Uuid,
    pub derivative: Uuid,
}

pub async fn seed_base(pool: &PgPool, account: Uuid) -> sqlx::Result<Base> {
    let media = Uuid::now_v7();
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, 'original', $3, 'image/jpeg')",
    )
    .bind(media)
    .bind(account)
    .bind(format!("k/{media}"))
    .execute(pool)
    .await?;

    let card = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_card (id, source, prompt_text, locale)
         values ($1, 'curated', 'Wear something blue', 'en')",
    )
    .bind(card)
    .execute(pool)
    .await?;

    let item = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq)
         values ($1, $2, 'top', 1)",
    )
    .bind(item)
    .bind(account)
    .execute(pool)
    .await?;

    let photo = Uuid::now_v7();
    sqlx::query(
        "insert into photo (id, account_id, media_object_id, source, change_seq)
         values ($1, $2, $3, 'capture', 2)",
    )
    .bind(photo)
    .bind(account)
    .bind(media)
    .execute(pool)
    .await?;

    let derivative = Uuid::now_v7();
    sqlx::query(
        "insert into photo_derivative (id, account_id, photo_id, media_object_id, change_seq)
         values ($1, $2, $3, $4, 3)",
    )
    .bind(derivative)
    .bind(account)
    .bind(photo)
    .bind(media)
    .execute(pool)
    .await?;

    Ok(Base {
        media,
        card,
        item,
        photo,
        derivative,
    })
}

pub async fn seed_item_details(pool: &PgPool, account: Uuid, base: &Base) -> sqlx::Result<()> {
    sqlx::query(
        "insert into item_fingerprint
             (id, account_id, item_id, version, color_lab, aspect_ratio, feature_print,
              mask_quality, source_photo_id, change_seq)
         values ($1, $2, $3, 'v1', $4, 0.75, $5, 0.9, $6, 4)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(vec![50.0_f32, 10.0, -20.0])
    .bind(vec![1_u8, 2, 3, 4])
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into item_cutout
             (id, account_id, item_id, media_object_id, source_photo_id, change_seq)
         values ($1, $2, $3, $4, $5, 5)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(base.media)
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into item_illustration
             (id, account_id, item_id, media_object_id, style_version, model,
              prompt_version, change_seq)
         values ($1, $2, $3, $4, 's1', 'a-model', 'p1', 6)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(base.media)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into wardrobe_item_conflict
             (id, account_id, item_id, field, value, revision, change_seq)
         values ($1, $2, $3, 'name', 'Blue shirt', 2, 11)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn seed_loop(pool: &PgPool, account: Uuid, base: &Base) -> sqlx::Result<(Uuid, Uuid)> {
    let completion = Uuid::now_v7();
    let challenge = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_completion
             (id, account_id, card_id, local_date, time_zone, completed_at, status,
              photo_id, current_derivative_id, change_seq)
         values ($1, $2, $3, current_date, 'Asia/Jakarta', now(), 'canonical', $4, $5, 7)",
    )
    .bind(completion)
    .bind(account)
    .bind(base.card)
    .bind(base.photo)
    .bind(base.derivative)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into active_challenge
             (id, account_id, card_id, accepted_at, local_date, time_zone, photo_id, change_seq)
         values ($1, $2, $3, now(), current_date, 'Asia/Jakarta', $4, 8)",
    )
    .bind(challenge)
    .bind(account)
    .bind(base.card)
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into wear_record
             (id, account_id, item_id, completion_id, source_photo_id, worn_on, change_seq)
         values ($1, $2, $3, $4, $5, current_date, 9)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(completion)
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into canvas_document
             (id, account_id, completion_id, derivative_id, schema_version,
              media_object_id, change_seq)
         values ($1, $2, $3, $4, 1, $5, 10)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(completion)
    .bind(base.derivative)
    .bind(base.media)
    .execute(pool)
    .await?;

    sqlx::query("insert into account_preference (account_id, change_seq) values ($1, 12)")
        .bind(account)
        .execute(pool)
        .await?;

    sqlx::query("update account set change_seq = 12 where id = $1")
        .bind(account)
        .execute(pool)
        .await?;

    Ok((completion, challenge))
}

pub async fn seed_every_kind(pool: &PgPool, account: Uuid) -> sqlx::Result<Seeded> {
    let base = seed_base(pool, account).await?;
    seed_item_details(pool, account, &base).await?;
    let (completion, challenge) = seed_loop(pool, account, &base).await?;
    Ok(Seeded {
        item: base.item,
        completion,
        challenge,
    })
}

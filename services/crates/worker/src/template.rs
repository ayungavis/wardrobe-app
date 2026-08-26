use std::fmt::Write as _;

use serde::Deserialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::illustration::image;
use crate::inference::{self, Accounting, Pinned, Provider};
use crate::openrouter::{self, Ask, Failure, Reference, Rejection};
use wardrobe_db::ClaimedJob;
use wardrobe_storage::Storage;

pub const CAPABILITY: &str = "outfit_template";
const MAX_IMAGE_BYTES: usize = 12 * 1024 * 1024;
const QUALITY_ATTEMPTS: i64 = 2;
const MAX_GARMENTS: usize = 6;

struct Settings {
    active_model: String,
    alternate_model: Option<String>,
    prompt_version: String,
    prompts: serde_json::Value,
    resolution: String,
    aspect_ratio: String,
    bounds: image::Bounds,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Payload {
    request_id: Uuid,
    template: String,
    person_media_id: Uuid,
    #[serde(default)]
    garments: Vec<Garment>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Garment {
    media_id: Uuid,
    name: Option<String>,
    wears: i64,
}

async fn settings(pool: &PgPool) -> Result<Settings, &'static str> {
    let config = inference::config(pool, CAPABILITY).await?;
    Ok(Settings {
        prompts: config.params.clone(),
        resolution: config
            .text("resolution")
            .unwrap_or_else(|| openrouter::DEFAULT_RESOLUTION.to_owned()),
        aspect_ratio: config
            .text("aspectRatio")
            .unwrap_or_else(|| openrouter::DEFAULT_ASPECT_RATIO.to_owned()),
        bounds: image::Bounds {
            max_bytes: image::DEFAULT_MAX_BYTES,
            max_pixels: image::DEFAULT_MAX_PIXELS,
        },
        active_model: config.active_model,
        alternate_model: config.alternate_model,
        prompt_version: config.prompt_version,
    })
}

fn payload_of(job: &ClaimedJob) -> Result<Payload, &'static str> {
    serde_json::from_value(job.payload.clone()).map_err(|_| "payload")
}

async fn owner(pool: &PgPool, media: Uuid) -> Result<Option<Uuid>, &'static str> {
    sqlx::query_scalar("select account_id from media_object where id = $1")
        .bind(media)
        .fetch_optional(pool)
        .await
        .map_err(|_| "database")
}

async fn key_of(pool: &PgPool, media: Uuid) -> Result<Option<String>, &'static str> {
    sqlx::query_scalar("select storage_key from media_object where id = $1")
        .bind(media)
        .fetch_optional(pool)
        .await
        .map_err(|_| "database")
}

fn describe(settings: &Settings, template: &str, garments: &[Garment]) -> String {
    let mut prompt = settings
        .prompts
        .get(template)
        .and_then(serde_json::Value::as_str)
        .unwrap_or("Compose a fashion lookbook page from the reference images.")
        .to_owned();

    prompt.push_str(
        " The first reference image is the person; every image after it is one garment, \
         in this order:",
    );
    for (index, garment) in garments.iter().enumerate() {
        let name = garment
            .name
            .as_deref()
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .unwrap_or("garment");
        let _ = write!(
            prompt,
            " {}. {name} — worn {} times.",
            index + 1,
            garment.wears
        );
    }
    prompt.push_str(" Print each garment's name and its wear count under it exactly as written.");
    prompt
}

/// # Errors
///
/// Returns a classified code when the provider, the object store, or the
/// database refuses.
pub async fn render_for(
    pool: &PgPool,
    storage: &Storage,
    provider: &Provider,
    job: &ClaimedJob,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let payload = payload_of(job)?;
    let Some(account) = owner(pool, payload.person_media_id).await? else {
        return Ok(());
    };
    let settings = settings(pool).await?;
    let pinned = inference::pin(
        pool,
        job.id,
        &settings.active_model,
        settings.alternate_model.as_deref(),
        QUALITY_ATTEMPTS,
    )
    .await?;

    let Some(person) = key_of(pool, payload.person_media_id).await? else {
        return Ok(());
    };
    let mut keys = vec![person];
    for garment in payload.garments.iter().take(MAX_GARMENTS) {
        let Some(key) = key_of(pool, garment.media_id).await? else {
            return Ok(());
        };
        keys.push(key);
    }

    if !inference::within_limits(pool, CAPABILITY, account).await? {
        return record(
            pool,
            job,
            account,
            &pinned,
            &settings,
            "skipped_limit",
            None,
            None,
        )
        .await;
    }

    let mut bytes = Vec::with_capacity(keys.len());
    for key in &keys {
        let raw = storage.get(key).await.map_err(|_| "object_store")?;
        match image::prepare(&raw, settings.bounds) {
            Ok(prepared) => bytes.push(prepared),
            Err(rejection) => {
                tracing::warn!(
                    job.id = %job.id,
                    rejection = rejection.code(),
                    "a reference cannot be sent, so no render was attempted"
                );
                return Ok(());
            }
        }
    }
    let references: Vec<Reference<'_>> = bytes
        .iter()
        .map(|bytes| Reference {
            bytes,
            content_type: "image/png",
        })
        .collect();

    let started = std::time::Instant::now();
    let outcome = openrouter::render(
        &provider.client,
        &provider.base_url,
        &provider.api_key,
        &Ask {
            model: &pinned.model,
            prompt: &describe(&settings, &payload.template, &payload.garments),
            references: &references,
            resolution: &settings.resolution,
            aspect_ratio: &settings.aspect_ratio,
            seed: pinned.seed,
        },
    )
    .await;
    let latency_ms = i32::try_from(started.elapsed().as_millis()).ok();

    settle(
        pool,
        storage,
        job,
        account,
        &payload,
        &settings,
        &pinned,
        outcome,
        latency_ms,
        final_attempt,
    )
    .await
}

#[expect(
    clippy::too_many_arguments,
    reason = "one call site, all of it required"
)]
async fn settle(
    pool: &PgPool,
    storage: &Storage,
    job: &ClaimedJob,
    account: Uuid,
    payload: &Payload,
    settings: &Settings,
    pinned: &Pinned,
    outcome: Result<openrouter::Rendered, Rejection>,
    latency_ms: Option<i32>,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let rendered = match outcome {
        Ok(rendered) => rendered,
        Err(rejection) => {
            let failure = rejection.failure;
            record(
                pool,
                job,
                account,
                pinned,
                settings,
                failure.status(),
                latency_ms,
                rejection.http_status.map(i32::from),
            )
            .await?;
            if !final_attempt && worth_another_attempt(failure, pinned) {
                return Err("provider_retryable");
            }
            return Ok(());
        }
    };

    if rendered.image.len() > MAX_IMAGE_BYTES {
        record(
            pool,
            job,
            account,
            pinned,
            settings,
            Failure::InvalidOutput.status(),
            latency_ms,
            None,
        )
        .await?;
        if !final_attempt && worth_another_attempt(Failure::InvalidOutput, pinned) {
            return Err("provider_retryable");
        }
        return Ok(());
    }

    record(
        pool,
        job,
        account,
        pinned,
        settings,
        "succeeded",
        latency_ms,
        Some(200),
    )
    .await?;
    publish(pool, storage, account, payload, settings, pinned, &rendered).await
}

fn worth_another_attempt(failure: Failure, pinned: &Pinned) -> bool {
    match failure {
        Failure::Unavailable => true,
        Failure::Ineligible => false,
        Failure::Refused => pinned.another_model_available,
        Failure::InvalidOutput => pinned.another_model_available || pinned.quality_attempts_left,
    }
}

#[expect(
    clippy::too_many_arguments,
    reason = "one call site, all of it required"
)]
async fn record(
    pool: &PgPool,
    job: &ClaimedJob,
    account: Uuid,
    pinned: &Pinned,
    settings: &Settings,
    status: &str,
    latency_ms: Option<i32>,
    http_status: Option<i32>,
) -> Result<(), &'static str> {
    inference::record(
        pool,
        CAPABILITY,
        job,
        account,
        pinned,
        &settings.prompt_version,
        &Accounting {
            status,
            provider_route: None,
            latency_ms,
            input_tokens: None,
            output_tokens: None,
            http_status,
        },
    )
    .await
}

async fn publish(
    pool: &PgPool,
    storage: &Storage,
    account: Uuid,
    payload: &Payload,
    settings: &Settings,
    pinned: &Pinned,
    rendered: &openrouter::Rendered,
) -> Result<(), &'static str> {
    let media = Uuid::now_v7();
    let key = format!("{account}/template/{media}");
    storage
        .put(&key, rendered.image.clone(), &rendered.content_type)
        .await
        .map_err(|_| "object_store")?;

    let mut tx = pool.begin().await.map_err(|_| "database")?;
    sqlx::query(
        "insert into media_object
             (id, account_id, kind, storage_key, content_type, byte_size, uploaded_at)
         values ($1, $2, 'derivative', $3, $4, $5, now())",
    )
    .bind(media)
    .bind(account)
    .bind(&key)
    .bind(&rendered.content_type)
    .bind(i64::try_from(rendered.image.len()).unwrap_or(i64::MAX))
    .execute(&mut *tx)
    .await
    .map_err(|_| "database")?;

    let seq = wardrobe_db::next_change_seq(&mut tx, account)
        .await
        .map_err(|_| "database")?;
    sqlx::query(
        "insert into outfit_template
             (id, account_id, request_id, media_object_id, template, model, prompt_version,
              change_seq)
         values ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(payload.request_id)
    .bind(media)
    .bind(&payload.template)
    .bind(&pinned.model)
    .bind(&settings.prompt_version)
    .bind(seq)
    .execute(&mut *tx)
    .await
    .map_err(|_| "database")?;

    tx.commit().await.map_err(|_| "database")
}

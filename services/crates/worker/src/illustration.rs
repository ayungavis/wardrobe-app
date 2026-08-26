pub mod image;
pub mod sticker;

use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_db::ClaimedJob;
use wardrobe_storage::Storage;

pub use crate::inference::Provider;
use crate::inference::{self, Accounting, Pinned};
pub use crate::openrouter;
use openrouter::{Ask, Failure, Rejection};

pub const STYLE_VERSION: &str = "v1";
pub const CAPABILITY: &str = "illustration";
const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
const QUALITY_ATTEMPTS: i64 = 2;
const DEFAULT_PROMPT: &str = "Redraw this single garment as a clean flat-lay product illustration on \
     a plain background. Draw the garment only. Do not draw a person, a body, a mannequin, or anyone \
     wearing it.";

struct Settings {
    active_model: String,
    alternate_model: Option<String>,
    prompt_version: String,
    prompt: String,
    resolution: String,
    aspect_ratio: String,
    bounds: image::Bounds,
}

struct Cutout {
    storage_key: String,
}

fn positive(configured: Option<i64>) -> Option<u64> {
    configured
        .filter(|value| *value > 0)
        .and_then(|value| u64::try_from(value).ok())
}

async fn settings(pool: &PgPool) -> Result<Settings, &'static str> {
    let config = inference::config(pool, CAPABILITY).await?;
    Ok(Settings {
        prompt: config
            .text("prompt")
            .unwrap_or_else(|| DEFAULT_PROMPT.to_owned()),
        resolution: config
            .text("resolution")
            .unwrap_or_else(|| openrouter::DEFAULT_RESOLUTION.to_owned()),
        aspect_ratio: config
            .text("aspectRatio")
            .unwrap_or_else(|| openrouter::DEFAULT_ASPECT_RATIO.to_owned()),
        bounds: image::Bounds {
            max_bytes: positive(config.integer("maxInputBytes"))
                .unwrap_or(image::DEFAULT_MAX_BYTES),
            max_pixels: positive(config.integer("maxInputPixels"))
                .unwrap_or(image::DEFAULT_MAX_PIXELS),
        },
        active_model: config.active_model,
        alternate_model: config.alternate_model,
        prompt_version: config.prompt_version,
    })
}

async fn cutout_for(pool: &PgPool, item: Uuid) -> Result<Option<Cutout>, &'static str> {
    sqlx::query_as(
        "select m.storage_key
           from item_cutout c
           join media_object m on m.id = c.media_object_id
          where c.item_id = $1 and c.deleted_at is null
          order by c.change_seq desc
          limit 1",
    )
    .bind(item)
    .fetch_optional(pool)
    .await
    .map(|row: Option<(String,)>| row.map(|(storage_key,)| Cutout { storage_key }))
    .map_err(|_| "database")
}

async fn set_state(
    pool: &PgPool,
    account: Uuid,
    item: Uuid,
    state: &str,
) -> Result<(), &'static str> {
    let mut conn = pool.acquire().await.map_err(|_| "database")?;
    let seq = wardrobe_db::next_change_seq(&mut conn, account)
        .await
        .map_err(|_| "database")?;
    drop(conn);

    sqlx::query("update wardrobe_item set illustration_state = $2, change_seq = $3 where id = $1")
        .bind(item)
        .bind(state)
        .bind(seq)
        .execute(pool)
        .await
        .map(|_| ())
        .map_err(|_| "database")
}

// ------------------------------------------------------------------ the work

struct Work<'a> {
    pool: &'a PgPool,
    storage: &'a Storage,
    job: &'a ClaimedJob,
    account: Uuid,
    item: Uuid,
    settings: &'a Settings,
    pinned: &'a Pinned,
}

fn item_of(job: &ClaimedJob) -> Result<Uuid, &'static str> {
    job.payload
        .get("itemId")
        .and_then(serde_json::Value::as_str)
        .and_then(|raw| Uuid::parse_str(raw).ok())
        .ok_or("unusable_payload")
}

#[derive(sqlx::FromRow)]
struct Subject {
    category: String,
    name: Option<String>,
    garment_type: Option<String>,
    color: Option<String>,
    description: Option<String>,
}

async fn subject(pool: &PgPool, item: Uuid) -> Result<Option<Subject>, &'static str> {
    sqlx::query_as(
        "select category, name, garment_type, color, description
           from wardrobe_item where id = $1",
    )
    .bind(item)
    .fetch_optional(pool)
    .await
    .map_err(|_| "database")
}

fn note_of(job: &ClaimedJob) -> Option<String> {
    job.payload
        .get("note")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|note| !note.is_empty())
        .map(ToOwned::to_owned)
}

// --- The model is shown a cut-out with no context, so a pair of shorts comes
// back as a shirt unless the request says what it is looking at.
fn describe(template: &str, subject: Option<&Subject>, note: Option<&str>) -> String {
    let mut prompt = template.to_owned();
    prompt.push(' ');
    prompt.push_str(sticker::FRAMING_RULE);
    if let Some(subject) = subject {
        let mut facts = vec![format!("category: {}", subject.category)];
        for (label, value) in [
            ("name", subject.name.as_deref()),
            ("type", subject.garment_type.as_deref()),
            ("colour", subject.color.as_deref()),
            ("notes", subject.description.as_deref()),
        ] {
            if let Some(value) = value.map(str::trim).filter(|value| !value.is_empty()) {
                facts.push(format!("{label}: {value}"));
            }
        }
        prompt.push_str(" The garment is described as — ");
        prompt.push_str(&facts.join("; "));
        prompt.push('.');
    }
    if let Some(note) = note {
        prompt.push_str(" The wearer adds: ");
        prompt.push_str(note);
    }
    prompt
}

async fn owner(pool: &PgPool, item: Uuid) -> Result<Option<Uuid>, &'static str> {
    sqlx::query_scalar("select account_id from wardrobe_item where id = $1 and deleted_at is null")
        .bind(item)
        .fetch_optional(pool)
        .await
        .map_err(|_| "database")
}

/// # Errors
///
/// Returns a classified code. `provider_unavailable` asks for a retry; every
/// other outcome settles the item and reports success, because retrying a
/// refusal spends money to be told the same thing.
pub async fn render_for(
    pool: &PgPool,
    storage: &Storage,
    provider: &Provider,
    job: &ClaimedJob,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let item = item_of(job)?;
    let Some(account) = owner(pool, item).await? else {
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
    let prompt = describe(
        &settings.prompt,
        subject(pool, item).await?.as_ref(),
        note_of(job).as_deref(),
    );

    let Some(cutout) = cutout_for(pool, item).await? else {
        return set_state(pool, account, item, "failed").await;
    };

    if !inference::within_limits(pool, CAPABILITY, account).await? {
        inference::record(
            pool,
            CAPABILITY,
            job,
            account,
            &pinned,
            &settings.prompt_version,
            &Accounting {
                status: "skipped_limit",
                provider_route: None,
                latency_ms: None,
                input_tokens: None,
                output_tokens: None,
                http_status: None,
            },
        )
        .await?;
        return set_state(pool, account, item, "failed").await;
    }

    let bytes = storage
        .get(&cutout.storage_key)
        .await
        .map_err(|_| "object_store")?;
    let bytes = match image::prepare(&bytes, settings.bounds) {
        Ok(prepared) => prepared,
        Err(rejection) => {
            tracing::warn!(
                job.id = %job.id,
                rejection = rejection.code(),
                "the cut-out cannot be sent, so no render was attempted"
            );
            return set_state(pool, account, item, "failed").await;
        }
    };

    set_state(pool, account, item, "rendering").await?;

    let started = std::time::Instant::now();
    let outcome = openrouter::render(
        &provider.client,
        &provider.base_url,
        &provider.api_key,
        &Ask {
            model: &pinned.model,
            prompt: &prompt,
            cutout: &bytes,
            content_type: "image/png",
            resolution: &settings.resolution,
            aspect_ratio: &settings.aspect_ratio,
            seed: pinned.seed,
        },
    )
    .await;
    let latency_ms = i32::try_from(started.elapsed().as_millis()).ok();

    let work = Work {
        pool,
        storage,
        job,
        account,
        item,
        settings: &settings,
        pinned: &pinned,
    };
    settle(&work, outcome, latency_ms, final_attempt).await
}

async fn settle(
    work: &Work<'_>,
    outcome: Result<openrouter::Rendered, Rejection>,
    latency_ms: Option<i32>,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let rendered = match outcome {
        Ok(rendered) => rendered,
        Err(rejection) => {
            let failure = rejection.failure;
            tracing::warn!(
                rejection = failure.status(),
                provider.status = rejection.http_status,
                "the provider declined the render"
            );
            inference::record(
                work.pool,
                CAPABILITY,
                work.job,
                work.account,
                work.pinned,
                &work.settings.prompt_version,
                &Accounting {
                    status: failure.status(),
                    provider_route: None,
                    latency_ms,
                    input_tokens: None,
                    output_tokens: None,
                    http_status: rejection.http_status.map(i32::from),
                },
            )
            .await?;

            if !final_attempt && worth_another_attempt(failure, work.pinned) {
                return Err("provider_retryable");
            }
            return set_state(work.pool, work.account, work.item, "failed").await;
        }
    };

    let unusable = rendered.image.len() > MAX_IMAGE_BYTES
        || image::verify_generation(
            &rendered.image,
            &work.settings.resolution,
            &work.settings.aspect_ratio,
        )
        .is_err();
    inference::record(
        work.pool,
        CAPABILITY,
        work.job,
        work.account,
        work.pinned,
        &work.settings.prompt_version,
        &Accounting {
            status: if unusable {
                "invalid_output"
            } else {
                "succeeded"
            },
            provider_route: rendered.provider_route.clone(),
            latency_ms,
            input_tokens: rendered.input_tokens,
            output_tokens: rendered.output_tokens,
            http_status: None,
        },
    )
    .await?;

    if unusable {
        if !final_attempt && worth_another_attempt(Failure::InvalidOutput, work.pinned) {
            return Err("provider_retryable");
        }
        return set_state(work.pool, work.account, work.item, "failed").await;
    }

    hand_off(work, &rendered).await
}

fn worth_another_attempt(failure: Failure, pinned: &Pinned) -> bool {
    match failure {
        Failure::Unavailable => true,
        Failure::Ineligible => false,
        Failure::Refused => pinned.another_model_available,
        Failure::InvalidOutput => pinned.another_model_available || pinned.quality_attempts_left,
    }
}

async fn hand_off(work: &Work<'_>, rendered: &openrouter::Rendered) -> Result<(), &'static str> {
    let media = Uuid::now_v7();
    let key = format!("{}/illustration/{media}", work.account);
    work.storage
        .put(&key, rendered.image.clone(), &rendered.content_type)
        .await
        .map_err(|_| "object_store")?;

    let mut tx = work.pool.begin().await.map_err(|_| "database")?;
    sqlx::query(
        "insert into media_object
             (id, account_id, kind, storage_key, content_type, byte_size, uploaded_at)
         values ($1, $2, 'illustration', $3, $4, $5, now())",
    )
    .bind(media)
    .bind(work.account)
    .bind(&key)
    .bind(&rendered.content_type)
    .bind(i64::try_from(rendered.image.len()).unwrap_or(i64::MAX))
    .execute(&mut *tx)
    .await
    .map_err(|_| "database")?;

    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload)
         values ($1, $2, $3, $4, jsonb_build_object(
             'itemId', $5::text, 'mediaId', $4,
             'model', $6::text, 'promptVersion', $7::text, 'styleVersion', $8::text))
         on conflict (kind, dedupe_key) do nothing",
    )
    .bind(Uuid::now_v7())
    .bind(work.account)
    .bind(wardrobe_db::STYLISE_ILLUSTRATION)
    .bind(media.to_string())
    .bind(work.item.to_string())
    .bind(&work.pinned.model)
    .bind(&work.settings.prompt_version)
    .bind(wardrobe_db::STYLE_VERSION)
    .execute(&mut *tx)
    .await
    .map_err(|_| "database")?;

    tx.commit().await.map_err(|_| "database")
}

// ---------------------------------------------------------------- stylising

struct Stylise {
    item: Uuid,
    media: Uuid,
    model: String,
    prompt_version: String,
    style_version: String,
}

fn stylise_payload(job: &ClaimedJob) -> Result<Stylise, &'static str> {
    let text = |key: &str| {
        job.payload
            .get(key)
            .and_then(serde_json::Value::as_str)
            .ok_or("payload")
    };
    let id = |key: &str| Uuid::parse_str(text(key)?).map_err(|_| "payload");

    Ok(Stylise {
        item: id("itemId")?,
        media: id("mediaId")?,
        model: text("model")?.to_owned(),
        prompt_version: text("promptVersion")?.to_owned(),
        style_version: text("styleVersion")?.to_owned(),
    })
}

/// # Errors
///
/// Returns a classified code when the generation cannot be loaded, separated
/// from its background, or stored.
pub async fn stylise_for(
    pool: &PgPool,
    storage: &Storage,
    job: &ClaimedJob,
) -> Result<(), &'static str> {
    let work = stylise_payload(job)?;
    let Some((account, key)) = generation(pool, work.media).await? else {
        return Ok(());
    };

    let bytes = storage.get(&key).await.map_err(|_| "object_store")?;
    let styled = match sticker::stylise(
        &bytes,
        sticker::Style::default(),
        sticker::MaskBounds::default(),
    ) {
        Ok(styled) => styled,
        Err(rejection) => {
            tracing::warn!(
                job.id = %job.id,
                rejection = rejection,
                "the generation could not become a sticker, so the cut-out stays"
            );
            return set_state(pool, account, work.item, "failed").await;
        }
    };

    publish(pool, storage, account, &work, styled).await
}

async fn generation(pool: &PgPool, media: Uuid) -> Result<Option<(Uuid, String)>, &'static str> {
    sqlx::query_as("select account_id, storage_key from media_object where id = $1")
        .bind(media)
        .fetch_optional(pool)
        .await
        .map_err(|_| "database")
}

async fn publish(
    pool: &PgPool,
    storage: &Storage,
    account: Uuid,
    work: &Stylise,
    styled: Vec<u8>,
) -> Result<(), &'static str> {
    let media = Uuid::now_v7();
    let key = format!("{account}/illustration/{media}");
    storage
        .put(&key, styled.clone(), "image/png")
        .await
        .map_err(|_| "object_store")?;

    let mut conn = pool.acquire().await.map_err(|_| "database")?;
    let seq = wardrobe_db::next_change_seq(&mut conn, account)
        .await
        .map_err(|_| "database")?;
    drop(conn);

    let mut tx = pool.begin().await.map_err(|_| "database")?;
    sqlx::query(
        "insert into media_object
             (id, account_id, kind, storage_key, content_type, byte_size, uploaded_at)
         values ($1, $2, 'illustration', $3, 'image/png', $4, now())",
    )
    .bind(media)
    .bind(account)
    .bind(&key)
    .bind(i64::try_from(styled.len()).unwrap_or(i64::MAX))
    .execute(&mut *tx)
    .await
    .map_err(|_| "database")?;

    let version = Uuid::now_v7();
    sqlx::query(
        "insert into item_illustration
             (id, account_id, item_id, media_object_id, style_version, model, prompt_version,
              change_seq)
         values ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(version)
    .bind(account)
    .bind(work.item)
    .bind(media)
    .bind(&work.style_version)
    .bind(&work.model)
    .bind(&work.prompt_version)
    .bind(seq)
    .execute(&mut *tx)
    .await
    .map_err(|_| "database")?;

    sqlx::query(
        "update wardrobe_item
            set illustration_state = 'ready', current_illustration_id = $2, change_seq = $3
          where id = $1",
    )
    .bind(work.item)
    .bind(version)
    .bind(seq)
    .execute(&mut *tx)
    .await
    .map_err(|_| "database")?;

    tx.commit().await.map_err(|_| "database")
}

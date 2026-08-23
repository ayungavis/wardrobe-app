pub mod openrouter;

use rust_decimal::Decimal;
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_db::ClaimedJob;
use wardrobe_storage::Storage;

use openrouter::{Ask, Failure};

pub const STYLE_VERSION: &str = "v1";
const CAPABILITY: &str = "illustration";
const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
const QUALITY_ATTEMPTS: i64 = 2;
const DEFAULT_PROMPT: &str = "Redraw this single garment as a clean flat-lay product illustration on \
     a plain background. Draw the garment only. Do not draw a person, a body, a mannequin, or anyone \
     wearing it.";

pub struct Provider {
    pub client: reqwest::Client,
    pub base_url: String,
    pub api_key: String,
}

struct Settings {
    active_model: String,
    alternate_model: Option<String>,
    prompt_version: String,
    prompt: String,
    resolution: String,
    aspect_ratio: String,
}

struct Cutout {
    storage_key: String,
    content_type: String,
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn ready(pool: &PgPool) -> sqlx::Result<bool> {
    let (enabled,): (bool,) = sqlx::query_as(
        "select exists (
             select 1 from ai_model_config
              where capability = $1 and enabled
         ) and exists (
             select 1 from ai_provider_allowlist where revoked_at is null
         )",
    )
    .bind(CAPABILITY)
    .fetch_one(pool)
    .await?;
    Ok(enabled)
}

#[derive(sqlx::FromRow)]
struct ConfigRow {
    active_model: String,
    alternate_model: Option<String>,
    prompt_version: String,
    prompt: Option<String>,
    resolution: Option<String>,
    aspect_ratio: Option<String>,
}

async fn settings(pool: &PgPool) -> Result<Settings, &'static str> {
    let row: Option<ConfigRow> = sqlx::query_as(
        "select active_model, alternate_model, prompt_version,
                params->>'prompt' as prompt,
                params->>'resolution' as resolution,
                params->>'aspectRatio' as aspect_ratio
           from ai_model_config
          where capability = $1 and enabled",
    )
    .bind(CAPABILITY)
    .fetch_optional(pool)
    .await
    .map_err(|_| "database")?;

    let row = row.ok_or("capability_disabled")?;
    Ok(Settings {
        active_model: row.active_model,
        alternate_model: row.alternate_model,
        prompt_version: row.prompt_version,
        prompt: row.prompt.unwrap_or_else(|| DEFAULT_PROMPT.to_owned()),
        resolution: row
            .resolution
            .unwrap_or_else(|| openrouter::DEFAULT_RESOLUTION.to_owned()),
        aspect_ratio: row
            .aspect_ratio
            .unwrap_or_else(|| openrouter::DEFAULT_ASPECT_RATIO.to_owned()),
    })
}

async fn cutout_for(pool: &PgPool, item: Uuid) -> Result<Option<Cutout>, &'static str> {
    sqlx::query_as(
        "select m.storage_key, m.content_type
           from item_cutout c
           join media_object m on m.id = c.media_object_id
          where c.item_id = $1 and c.deleted_at is null
          order by c.change_seq desc
          limit 1",
    )
    .bind(item)
    .fetch_optional(pool)
    .await
    .map(|row: Option<(String, String)>| {
        row.map(|(storage_key, content_type)| Cutout {
            storage_key,
            content_type,
        })
    })
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

// ------------------------------------------------------------------- limits

async fn within_limits(pool: &PgPool, account: Uuid) -> Result<bool, &'static str> {
    let limits: Vec<(String, i32, Option<i64>, Option<Decimal>)> = sqlx::query_as(
        "select scope, window_seconds, max_requests, max_cost_usd
           from ai_usage_limit
          where enabled and (capability is null or capability = $1)",
    )
    .bind(CAPABILITY)
    .fetch_all(pool)
    .await
    .map_err(|_| "database")?;

    for (scope, window_seconds, max_requests, max_cost_usd) in limits {
        let scoped = (scope == "account").then_some(account);
        let (requests, cost): (i64, Option<Decimal>) = sqlx::query_as(
            "select count(*), coalesce(sum(cost_usd), 0)
               from ai_inference_attempt
              where capability = $1
                and created_at > now() - make_interval(secs => $2)
                and ($3::uuid is null or account_id = $3)",
        )
        .bind(CAPABILITY)
        .bind(f64::from(window_seconds))
        .bind(scoped)
        .fetch_one(pool)
        .await
        .map_err(|_| "database")?;

        if max_requests.is_some_and(|max| requests >= max) {
            return Ok(false);
        }
        if max_cost_usd.is_some_and(|max| cost.unwrap_or_default() >= max) {
            return Ok(false);
        }
    }

    Ok(true)
}

// -------------------------------------------------------------- the attempt

struct Pinned {
    model: String,
    seed: i64,
    attempt_no: i32,
    another_model_available: bool,
    quality_attempts_left: bool,
}

fn fresh_seed() -> i64 {
    let bytes = Uuid::now_v7().into_bytes();
    i64::from(u32::from_be_bytes([
        bytes[8], bytes[9], bytes[10], bytes[11],
    ]))
}

async fn pin(pool: &PgPool, job: Uuid, settings: &Settings) -> Result<Pinned, &'static str> {
    let earlier: Vec<(String, Option<i64>, String)> = sqlx::query_as(
        "select model, seed, status from ai_inference_attempt
          where job_id = $1 order by attempt_no",
    )
    .bind(job)
    .fetch_all(pool)
    .await
    .map_err(|_| "database")?;

    let attempt_no = i32::try_from(earlier.len()).unwrap_or(i32::MAX) + 1;
    let invalid_so_far = earlier
        .iter()
        .filter(|(_, _, status)| status == "invalid_output")
        .count();
    let invalid_so_far = i64::try_from(invalid_so_far).unwrap_or(i64::MAX);
    let unused_alternate = settings
        .alternate_model
        .as_ref()
        .filter(|alternate| !earlier.iter().any(|(model, _, _)| &model == alternate));

    let Some((first_model, first_seed, last_status)) = earlier.last() else {
        return Ok(Pinned {
            model: settings.active_model.clone(),
            seed: fresh_seed(),
            attempt_no,
            another_model_available: settings.alternate_model.is_some(),
            quality_attempts_left: QUALITY_ATTEMPTS > 0,
        });
    };

    let escalating = matches!(last_status.as_str(), "refused" | "invalid_output");
    let (model, seed) = match unused_alternate {
        Some(alternate) if escalating => (alternate.clone(), fresh_seed()),
        _ => (first_model.clone(), first_seed.unwrap_or_else(fresh_seed)),
    };

    Ok(Pinned {
        model,
        seed,
        attempt_no,
        another_model_available: unused_alternate.is_some(),
        quality_attempts_left: invalid_so_far < QUALITY_ATTEMPTS,
    })
}

struct Accounting<'a> {
    status: &'a str,
    provider_route: Option<String>,
    latency_ms: Option<i32>,
    input_tokens: Option<i64>,
    output_tokens: Option<i64>,
}

async fn record(
    pool: &PgPool,
    job: &ClaimedJob,
    account: Uuid,
    pinned: &Pinned,
    settings: &Settings,
    accounting: &Accounting<'_>,
) -> Result<(), &'static str> {
    sqlx::query(
        "insert into ai_inference_attempt
             (id, account_id, job_id, capability, attempt_no, model, prompt_version,
              provider_route, status, latency_ms, input_tokens, output_tokens, seed)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(job.id)
    .bind(CAPABILITY)
    .bind(pinned.attempt_no)
    .bind(&pinned.model)
    .bind(&settings.prompt_version)
    .bind(accounting.provider_route.as_ref())
    .bind(accounting.status)
    .bind(accounting.latency_ms)
    .bind(accounting.input_tokens)
    .bind(accounting.output_tokens)
    .bind(pinned.seed)
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
    let pinned = pin(pool, job.id, &settings).await?;

    let Some(cutout) = cutout_for(pool, item).await? else {
        return set_state(pool, account, item, "failed").await;
    };

    if !within_limits(pool, account).await? {
        record(
            pool,
            job,
            account,
            &pinned,
            &settings,
            &Accounting {
                status: "skipped_limit",
                provider_route: None,
                latency_ms: None,
                input_tokens: None,
                output_tokens: None,
            },
        )
        .await?;
        return set_state(pool, account, item, "failed").await;
    }

    set_state(pool, account, item, "rendering").await?;
    let bytes = storage
        .get(&cutout.storage_key)
        .await
        .map_err(|_| "object_store")?;

    let started = std::time::Instant::now();
    let outcome = openrouter::render(
        &provider.client,
        &provider.base_url,
        &provider.api_key,
        &Ask {
            model: &pinned.model,
            prompt: &settings.prompt,
            cutout: &bytes,
            content_type: &cutout.content_type,
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
    outcome: Result<openrouter::Rendered, Failure>,
    latency_ms: Option<i32>,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let rendered = match outcome {
        Ok(rendered) => rendered,
        Err(failure) => {
            record(
                work.pool,
                work.job,
                work.account,
                work.pinned,
                work.settings,
                &Accounting {
                    status: failure.status(),
                    provider_route: None,
                    latency_ms,
                    input_tokens: None,
                    output_tokens: None,
                },
            )
            .await?;

            if !final_attempt && worth_another_attempt(failure, work.pinned) {
                return Err("provider_retryable");
            }
            return set_state(work.pool, work.account, work.item, "failed").await;
        }
    };

    let oversize = rendered.image.len() > MAX_IMAGE_BYTES;
    record(
        work.pool,
        work.job,
        work.account,
        work.pinned,
        work.settings,
        &Accounting {
            status: if oversize {
                "invalid_output"
            } else {
                "succeeded"
            },
            provider_route: rendered.provider_route.clone(),
            latency_ms,
            input_tokens: rendered.input_tokens,
            output_tokens: rendered.output_tokens,
        },
    )
    .await?;

    if oversize {
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

pub mod illustration;

use std::future::Future;

use chrono::{DateTime, Duration, Utc};
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_db::ClaimedJob;
use wardrobe_storage::Storage;

pub const SWEEP_MEDIA: &str = "sweepMedia";

#[must_use]
pub fn kinds(illustration: bool, storage: bool) -> Vec<&'static str> {
    let mut kinds = vec![SWEEP_MEDIA];
    if illustration {
        kinds.push(wardrobe_db::ILLUSTRATION);
    }
    if storage {
        kinds.push(wardrobe_db::STYLISE_ILLUSTRATION);
    }
    kinds
}

// ponytail: a job still running when this elapses is handed to a second worker
// and runs twice. Raise it above the slowest handler, or move to a heartbeat
// the handler refreshes, once any job can outlive it.
pub const STALL_AFTER_MINUTES: i64 = 15;

// ponytail: 300s is roughly twice the 147s a live Seedream render measured in
// T15h. Raise it from a new measurement, and keep it under STALL_AFTER_MINUTES
// or the reclaimer races a request that is still running.
pub const PROVIDER_TIMEOUT_SECONDS: u64 = 300;
pub const SWEEP_GRACE_HOURS: i64 = 24;
const SWEEP_BATCH: i64 = 500;
const MAX_BACKOFF_SECONDS: i32 = 3600;

#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    Succeeded,
    Retrying,
    Failed,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Swept {
    pub removed: u64,
    pub stamped: u64,
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn enqueue_sweep(pool: &PgPool, at: DateTime<Utc>) -> sqlx::Result<bool> {
    let done = sqlx::query(
        "insert into job (id, kind, dedupe_key) values ($1, $2, $3)
         on conflict (kind, dedupe_key) do nothing",
    )
    .bind(Uuid::now_v7())
    .bind(SWEEP_MEDIA)
    .bind(at.format("%Y-%m-%dT%H").to_string())
    .execute(pool)
    .await?;

    Ok(done.rows_affected() > 0)
}

/// # Errors
///
/// Returns any database error unchanged. The handler reports failure as a
/// `&'static str`, which is what keeps a provider's own words out of
/// `last_error_code`: runtime text cannot be produced at that type.
pub async fn run_one<F, Fut>(pool: &PgPool, kind: &str, handle: F) -> sqlx::Result<Option<Outcome>>
where
    F: FnOnce(ClaimedJob) -> Fut,
    Fut: Future<Output = Result<(), &'static str>>,
{
    let mut conn = pool.acquire().await?;
    let Some(job) = wardrobe_db::claim_job(&mut conn, kind).await? else {
        return Ok(None);
    };
    drop(conn);

    let id = job.id;
    let attempts = job.attempts;
    let max_attempts: i32 = sqlx::query_scalar("select max_attempts from job where id = $1")
        .bind(id)
        .fetch_one(pool)
        .await?;

    let Err(code) = handle(job).await else {
        sqlx::query(
            "update job set status = 'succeeded', finished_at = now(), last_error_code = null
              where id = $1",
        )
        .bind(id)
        .execute(pool)
        .await?;
        return Ok(Some(Outcome::Succeeded));
    };

    if attempts < max_attempts {
        sqlx::query(
            "update job
                set status = 'pending',
                    run_after = now() + make_interval(secs => $2),
                    last_error_code = $3
              where id = $1",
        )
        .bind(id)
        .bind(f64::from(backoff_seconds(attempts)))
        .bind(code)
        .execute(pool)
        .await?;
        tracing::warn!(job.code = code, job.attempts = attempts, "job retrying");
        return Ok(Some(Outcome::Retrying));
    }

    sqlx::query(
        "update job set status = 'failed', finished_at = now(), last_error_code = $2 where id = $1",
    )
    .bind(id)
    .bind(code)
    .execute(pool)
    .await?;
    tracing::error!(
        job.code = code,
        job.attempts = attempts,
        "job failed permanently"
    );
    Ok(Some(Outcome::Failed))
}

fn backoff_seconds(attempts: i32) -> i32 {
    60_i32
        .saturating_mul(2_i32.saturating_pow(attempts.max(1).unsigned_abs().min(16) - 1))
        .min(MAX_BACKOFF_SECONDS)
}

// -------------------------------------------------------------- sweeping media

const SWEEPABLE: &str = "select id, storage_key, kind
   from media_object m
  where m.uploaded_at is null
    and m.created_at < now() - $1::interval
    and not exists (select 1 from photo            where media_object_id = m.id)
    and not exists (select 1 from photo_derivative where media_object_id = m.id)
    and not exists (select 1 from item_cutout      where media_object_id = m.id)
    and not exists (select 1 from item_illustration where media_object_id = m.id)
    and not exists (
        select 1 from canvas_document
         where media_object_id = m.id or history_media_object_id = m.id
    )
  limit $2";

/// # Errors
///
/// Returns a classified code when the database or the object store refuses.
pub async fn sweep_media(
    pool: &PgPool,
    storage: &Storage,
    grace: Duration,
) -> Result<Swept, &'static str> {
    let candidates: Vec<(Uuid, String, String)> = sqlx::query_as(SWEEPABLE)
        .bind(grace)
        .bind(SWEEP_BATCH)
        .fetch_all(pool)
        .await
        .map_err(|_| "database")?;

    let mut swept = Swept::default();
    for (id, key, kind) in candidates {
        let found = storage.head(&key).await.map_err(|_| "object_store")?;
        if let Some(size) = found.filter(|size| {
            i64::try_from(*size).unwrap_or(i64::MAX) <= wardrobe_db::upload_cap(&kind)
        }) {
            sqlx::query(
                "update media_object set uploaded_at = now(), byte_size = $2 where id = $1",
            )
            .bind(id)
            .bind(i64::try_from(size).unwrap_or(i64::MAX))
            .execute(pool)
            .await
            .map_err(|_| "database")?;
            swept.stamped += 1;
        } else {
            sqlx::query("delete from media_object where id = $1")
                .bind(id)
                .execute(pool)
                .await
                .map_err(|_| "database")?;
            swept.removed += 1;
        }
    }

    Ok(swept)
}

#[cfg(test)]
mod tests {
    use super::{PROVIDER_TIMEOUT_SECONDS, STALL_AFTER_MINUTES};

    #[test]
    fn a_provider_call_gives_up_long_before_the_reclaimer_wakes() {
        let stall = u64::try_from(STALL_AFTER_MINUTES).expect("a positive threshold") * 60;
        assert!(
            PROVIDER_TIMEOUT_SECONDS < stall,
            "a request still running when the reclaimer fires is a second render, and a second bill"
        );
    }
}

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    local_date: NaiveDate,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Queued {
    local_date: NaiveDate,
    status: &'static str,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;

    let mut tx = pool.begin().await?;
    sqlx::query(
        "delete from challenge_card
          where account_id = $1 and local_date = $2 and source = 'generated'
            and not exists (
                select 1 from active_challenge a
                 where a.card_id = challenge_card.id and a.deleted_at is null
            )
            and not exists (
                select 1 from challenge_completion c where c.card_id = challenge_card.id
            )",
    )
    .bind(account_id)
    .bind(args.local_date)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload)
         values ($1, $2, $3, $4, $5)
         on conflict (kind, dedupe_key) do update
            set status = 'pending',
                attempts = 0,
                run_after = now(),
                started_at = null,
                finished_at = null,
                last_error_code = null,
                payload = excluded.payload",
    )
    .bind(Uuid::now_v7())
    .bind(account_id)
    .bind(wardrobe_db::CHALLENGE_DECK)
    .bind(format!("{account_id}:{}", args.local_date))
    .bind(serde_json::json!({
        "localDate": args.local_date.to_string(),
        "accountId": account_id.to_string(),
    }))
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    serde_json::to_value(Queued {
        local_date: args.local_date,
        status: "queued",
    })
    .map_err(|_| Error::BadRequest)
}

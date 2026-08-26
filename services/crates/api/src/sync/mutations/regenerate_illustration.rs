use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;

const NOTE_LIMIT: usize = 200;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    item_id: Uuid,
    #[serde(default)]
    note: Option<String>,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Queued {
    id: Uuid,
    illustration_state: String,
    change_seq: i64,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments and [`Error::NotFound`]
/// when this account has no such item.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;
    let note = args
        .note
        .map(|note| note.trim().chars().take(NOTE_LIMIT).collect::<String>())
        .filter(|note| !note.is_empty());

    let mut tx = pool.begin().await?;
    let owned: Option<(Uuid,)> = sqlx::query_as(
        "select id from wardrobe_item
          where id = $1 and account_id = $2 and deleted_at is null
          for update",
    )
    .bind(args.item_id)
    .bind(account_id)
    .fetch_optional(&mut *tx)
    .await?;
    if owned.is_none() {
        return Err(Error::NotFound);
    }

    let payload = match note {
        Some(note) => serde_json::json!({ "itemId": args.item_id.to_string(), "note": note }),
        None => serde_json::json!({ "itemId": args.item_id.to_string() }),
    };
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
    .bind(wardrobe_db::ILLUSTRATION)
    .bind(format!("{}:{}", args.item_id, wardrobe_db::STYLE_VERSION))
    .bind(payload)
    .execute(&mut *tx)
    .await?;

    let seq = super::next(&mut tx, account_id).await?;
    let queued: Queued = sqlx::query_as(
        "update wardrobe_item
            set illustration_state = 'queued', change_seq = $2
          where id = $1
      returning id, illustration_state, change_seq",
    )
    .bind(args.item_id)
    .bind(seq)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;

    serde_json::to_value(&queued).map_err(|_| Error::BadRequest)
}

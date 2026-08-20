use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    id: Uuid,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Tombstone {
    id: Uuid,
    deleted_at: Option<DateTime<Utc>>,
    change_seq: i64,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments and [`Error::NotFound`]
/// when this account has no such item.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;

    let mut tx = pool.begin().await?;
    let existing: Option<Tombstone> = sqlx::query_as(
        "select id, deleted_at, change_seq
           from wardrobe_item
          where id = $1 and account_id = $2
          for update",
    )
    .bind(args.id)
    .bind(account_id)
    .fetch_optional(&mut *tx)
    .await?;

    let Some(existing) = existing else {
        return Err(Error::NotFound);
    };

    if existing.deleted_at.is_some() {
        tx.commit().await?;
        return serialize(&existing);
    }

    let change_seq = wardrobe_db::next_change_seq(&mut tx, account_id).await?;
    let tombstone: Tombstone = sqlx::query_as(
        "update wardrobe_item
            set deleted_at = now(), change_seq = $2
          where id = $1
      returning id, deleted_at, change_seq",
    )
    .bind(args.id)
    .bind(change_seq)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;

    serialize(&tombstone)
}

fn serialize(tombstone: &Tombstone) -> Result<Value, Error> {
    serde_json::to_value(tombstone).map_err(|_| Error::BadRequest)
}

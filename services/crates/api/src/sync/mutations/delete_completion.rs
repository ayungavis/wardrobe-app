use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};
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
/// when this account has no such completion.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;

    let mut tx = pool.begin().await?;
    let existing: Option<Tombstone> = sqlx::query_as(
        "select id, deleted_at, change_seq
           from challenge_completion
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

    bury_wears(&mut tx, account_id, args.id).await?;
    bury_documents(&mut tx, account_id, args.id).await?;
    bury_orphaned_photos(&mut tx, account_id, args.id).await?;

    let change_seq = wardrobe_db::next_change_seq(&mut tx, account_id).await?;
    let tombstone: Tombstone = sqlx::query_as(
        "update challenge_completion
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

async fn bury_wears(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    completion: Uuid,
) -> Result<(), Error> {
    let ids: Vec<(Uuid,)> = sqlx::query_as(
        "select id from wear_record
          where completion_id = $1 and account_id = $2 and deleted_at is null
          for update",
    )
    .bind(completion)
    .bind(account_id)
    .fetch_all(&mut **tx)
    .await?;

    for (id,) in ids {
        let seq = super::next(tx, account_id).await?;
        sqlx::query("update wear_record set deleted_at = now(), change_seq = $2 where id = $1")
            .bind(id)
            .bind(seq)
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

async fn bury_documents(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    completion: Uuid,
) -> Result<(), Error> {
    let ids: Vec<(Uuid,)> = sqlx::query_as(
        "select id from canvas_document
          where completion_id = $1 and account_id = $2 and deleted_at is null
          for update",
    )
    .bind(completion)
    .bind(account_id)
    .fetch_all(&mut **tx)
    .await?;

    for (id,) in ids {
        let seq = super::next(tx, account_id).await?;
        sqlx::query("update canvas_document set deleted_at = now(), change_seq = $2 where id = $1")
            .bind(id)
            .bind(seq)
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

async fn bury_orphaned_photos(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    completion: Uuid,
) -> Result<(), Error> {
    let photos: Vec<(Uuid,)> = sqlx::query_as(
        "select p.id from photo p
           join completion_photo cp on cp.photo_id = p.id
          where cp.completion_id = $1 and p.account_id = $2 and p.deleted_at is null
            and not exists (
                select 1 from completion_photo other
                 where other.photo_id = p.id and other.completion_id <> $1
            )
          for update of p",
    )
    .bind(completion)
    .bind(account_id)
    .fetch_all(&mut **tx)
    .await?;

    for (photo,) in photos {
        let derivatives: Vec<(Uuid,)> = sqlx::query_as(
            "select id from photo_derivative where photo_id = $1 and deleted_at is null for update",
        )
        .bind(photo)
        .fetch_all(&mut **tx)
        .await?;

        for (id,) in derivatives {
            let seq = super::next(tx, account_id).await?;
            sqlx::query(
                "update photo_derivative set deleted_at = now(), change_seq = $2 where id = $1",
            )
            .bind(id)
            .bind(seq)
            .execute(&mut **tx)
            .await?;
        }

        let seq = super::next(tx, account_id).await?;
        sqlx::query("update photo set deleted_at = now(), change_seq = $2 where id = $1")
            .bind(photo)
            .bind(seq)
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

fn serialize(tombstone: &Tombstone) -> Result<Value, Error> {
    serde_json::to_value(tombstone).map_err(|_| Error::BadRequest)
}

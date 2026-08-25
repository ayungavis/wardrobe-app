use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::error::Error;

type Tx<'a> = Transaction<'a, Postgres>;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    winner_id: Uuid,
    loser_id: Uuid,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Tombstone {
    id: Uuid,
    deleted_at: Option<DateTime<Utc>>,
    change_seq: i64,
}

#[derive(sqlx::FromRow)]
struct Item {
    id: Uuid,
    current_illustration_id: Option<Uuid>,
    deleted_at: Option<DateTime<Utc>>,
    change_seq: i64,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments, a self-merge, or a
/// tombstoned winner, and [`Error::NotFound`] when this account does not own
/// both items.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;
    if args.winner_id == args.loser_id {
        return Err(Error::BadRequest);
    }

    let mut tx = pool.begin().await?;
    sqlx::query("select id from account where id = $1 for update")
        .bind(account_id)
        .execute(&mut *tx)
        .await?;

    let winner = item(&mut tx, account_id, args.winner_id).await?;
    let loser = item(&mut tx, account_id, args.loser_id).await?;
    if winner.deleted_at.is_some() {
        return Err(Error::BadRequest);
    }
    if loser.deleted_at.is_some() {
        tx.commit().await?;
        return serialize(&Tombstone {
            id: loser.id,
            deleted_at: loser.deleted_at,
            change_seq: loser.change_seq,
        });
    }

    drop_colliding_wears(&mut tx, account_id, &args).await?;
    move_children(&mut tx, account_id, &args, "wear_record").await?;
    move_children(&mut tx, account_id, &args, "item_fingerprint").await?;
    move_children(&mut tx, account_id, &args, "item_cutout").await?;
    adopt_illustration(&mut tx, account_id, &winner, &loser).await?;
    resolve_conflicts(&mut tx, account_id, args.loser_id).await?;

    let seq = super::next(&mut tx, account_id).await?;
    let tombstone: Tombstone = sqlx::query_as(
        "update wardrobe_item
            set deleted_at = now(), change_seq = $2
          where id = $1
      returning id, deleted_at, change_seq",
    )
    .bind(args.loser_id)
    .bind(seq)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;

    serialize(&tombstone)
}

async fn item(tx: &mut Tx<'_>, account_id: Uuid, id: Uuid) -> Result<Item, Error> {
    sqlx::query_as(
        "select id, current_illustration_id, deleted_at, change_seq
           from wardrobe_item
          where id = $1 and account_id = $2
          for update",
    )
    .bind(id)
    .bind(account_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(Error::NotFound)
}

async fn drop_colliding_wears(tx: &mut Tx<'_>, account_id: Uuid, args: &Args) -> Result<(), Error> {
    let colliding: Vec<(Uuid,)> = sqlx::query_as(
        "select l.id
           from wear_record l
          where l.item_id = $1 and l.account_id = $3 and l.deleted_at is null
            and l.source_photo_id is not null
            and exists (select 1 from wear_record w
                         where w.account_id = $3 and w.item_id = $2
                           and w.source_photo_id = l.source_photo_id
                           and w.deleted_at is null)",
    )
    .bind(args.loser_id)
    .bind(args.winner_id)
    .bind(account_id)
    .fetch_all(&mut **tx)
    .await?;

    for (id,) in colliding {
        let seq = super::next(tx, account_id).await?;
        sqlx::query("update wear_record set deleted_at = now(), change_seq = $2 where id = $1")
            .bind(id)
            .bind(seq)
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

async fn move_children(
    tx: &mut Tx<'_>,
    account_id: Uuid,
    args: &Args,
    table: &str,
) -> Result<(), Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(&format!(
        "select id from {table}
          where item_id = $1 and account_id = $2 and deleted_at is null"
    ))
    .bind(args.loser_id)
    .bind(account_id)
    .fetch_all(&mut **tx)
    .await?;

    for (id,) in rows {
        let seq = super::next(tx, account_id).await?;
        sqlx::query(&format!(
            "update {table} set item_id = $2, change_seq = $3 where id = $1"
        ))
        .bind(id)
        .bind(args.winner_id)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

async fn adopt_illustration(
    tx: &mut Tx<'_>,
    account_id: Uuid,
    winner: &Item,
    loser: &Item,
) -> Result<(), Error> {
    let (None, Some(illustration)) = (
        winner.current_illustration_id,
        loser.current_illustration_id,
    ) else {
        return Ok(());
    };

    let seq = super::next(tx, account_id).await?;
    sqlx::query("update item_illustration set item_id = $2, change_seq = $3 where id = $1")
        .bind(illustration)
        .bind(winner.id)
        .bind(seq)
        .execute(&mut **tx)
        .await?;

    let seq = super::next(tx, account_id).await?;
    sqlx::query(
        "update wardrobe_item set current_illustration_id = $2, change_seq = $3 where id = $1",
    )
    .bind(winner.id)
    .bind(illustration)
    .bind(seq)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn resolve_conflicts(tx: &mut Tx<'_>, account_id: Uuid, loser_id: Uuid) -> Result<(), Error> {
    let open: Vec<(Uuid,)> = sqlx::query_as(
        "select id from wardrobe_item_conflict
          where item_id = $1 and account_id = $2 and resolved_at is null",
    )
    .bind(loser_id)
    .bind(account_id)
    .fetch_all(&mut **tx)
    .await?;

    for (id,) in open {
        let seq = super::next(tx, account_id).await?;
        sqlx::query(
            "update wardrobe_item_conflict set resolved_at = now(), change_seq = $2 where id = $1",
        )
        .bind(id)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

fn serialize(tombstone: &Tombstone) -> Result<Value, Error> {
    serde_json::to_value(tombstone).map_err(|_| Error::BadRequest)
}

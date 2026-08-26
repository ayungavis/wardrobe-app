use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::error::Error;

mod items;

type Tx<'a> = Transaction<'a, Postgres>;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    completion_id: Uuid,
    card_id: Uuid,
    local_date: NaiveDate,
    time_zone: String,
    completed_at: DateTime<Utc>,
    photo: PhotoArgs,
    derivative: DerivativeArgs,
    document: DocumentArgs,
    #[serde(default)]
    layer_photo_ids: Vec<Uuid>,
    #[serde(default)]
    layer_photos: Vec<PhotoArgs>,
    #[serde(default)]
    items: Vec<items::ItemArgs>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PhotoArgs {
    id: Uuid,
    media_object_id: Uuid,
    source: String,
    captured_at: Option<DateTime<Utc>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DerivativeArgs {
    id: Uuid,
    media_object_id: Uuid,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DocumentArgs {
    id: Uuid,
    schema_version: i32,
    media_object_id: Uuid,
    history_media_object_id: Option<Uuid>,
    history_step_count: Option<i32>,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Completion {
    id: Uuid,
    #[serde(skip)]
    account_id: Uuid,
    status: String,
    local_date: NaiveDate,
    change_seq: i64,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments and [`Error::Conflict`]
/// when this completion id already belongs to a different account.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;
    let mut tx = pool.begin().await?;

    if let Some(stored) = stored(&mut tx, args.completion_id, account_id).await? {
        tx.commit().await?;
        return serialize(&stored);
    }

    let completion = write_all(&mut tx, account_id, &args)
        .await
        .map_err(from_the_client)?;
    tx.commit().await?;
    serialize(&completion)
}

fn serialize(completion: &Completion) -> Result<Value, Error> {
    serde_json::to_value(completion).map_err(|_| Error::BadRequest)
}

fn from_the_client(error: Error) -> Error {
    let Error::Internal(source) = &error else {
        return error;
    };
    match wardrobe_db::error_facts(source).sqlstate.as_deref() {
        Some("23503" | "23514") => Error::BadRequest,
        Some("23505") => Error::Conflict,
        _ => error,
    }
}

async fn stored(
    tx: &mut Tx<'_>,
    completion_id: Uuid,
    account_id: Uuid,
) -> Result<Option<Completion>, Error> {
    let found: Option<Completion> = sqlx::query_as(
        "select id, account_id, status, local_date, change_seq
           from challenge_completion
          where id = $1",
    )
    .bind(completion_id)
    .fetch_optional(&mut **tx)
    .await?;

    match found {
        Some(completion) if completion.account_id != account_id => Err(Error::Conflict),
        other => Ok(other),
    }
}

async fn canonical_status(
    tx: &mut Tx<'_>,
    account_id: Uuid,
    local_date: NaiveDate,
) -> Result<&'static str, Error> {
    sqlx::query("select id from account where id = $1 for update")
        .bind(account_id)
        .execute(&mut **tx)
        .await?;

    let taken: Option<(Uuid,)> = sqlx::query_as(
        "select id from challenge_completion
          where account_id = $1 and local_date = $2
            and status = 'canonical' and deleted_at is null",
    )
    .bind(account_id)
    .bind(local_date)
    .fetch_optional(&mut **tx)
    .await?;

    Ok(if taken.is_some() {
        "conflicting"
    } else {
        "canonical"
    })
}

async fn write_all(tx: &mut Tx<'_>, account_id: Uuid, args: &Args) -> Result<Completion, Error> {
    let status = canonical_status(tx, account_id, args.local_date).await?;

    let photo_seq = super::next(tx, account_id).await?;
    sqlx::query(
        "insert into photo (id, account_id, media_object_id, source, captured_at, change_seq)
         values ($1, $2, $3, $4, $5, $6)",
    )
    .bind(args.photo.id)
    .bind(account_id)
    .bind(args.photo.media_object_id)
    .bind(&args.photo.source)
    .bind(args.photo.captured_at)
    .bind(photo_seq)
    .execute(&mut **tx)
    .await?;

    for photo in &args.layer_photos {
        let seq = super::next(tx, account_id).await?;
        sqlx::query(
            "insert into photo (id, account_id, media_object_id, source, captured_at, change_seq)
             values ($1, $2, $3, $4, $5, $6)
             on conflict (id) do nothing",
        )
        .bind(photo.id)
        .bind(account_id)
        .bind(photo.media_object_id)
        .bind(&photo.source)
        .bind(photo.captured_at)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    }

    let derivative_seq = super::next(tx, account_id).await?;
    sqlx::query(
        "insert into photo_derivative (id, account_id, photo_id, media_object_id, change_seq)
         values ($1, $2, $3, $4, $5)",
    )
    .bind(args.derivative.id)
    .bind(account_id)
    .bind(args.photo.id)
    .bind(args.derivative.media_object_id)
    .bind(derivative_seq)
    .execute(&mut **tx)
    .await?;

    let completion_seq = super::next(tx, account_id).await?;
    let completion: Completion = sqlx::query_as(
        "insert into challenge_completion
             (id, account_id, card_id, local_date, time_zone, completed_at, status,
              photo_id, current_derivative_id, change_seq)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         returning id, account_id, status, local_date, change_seq",
    )
    .bind(args.completion_id)
    .bind(account_id)
    .bind(args.card_id)
    .bind(args.local_date)
    .bind(&args.time_zone)
    .bind(args.completed_at)
    .bind(status)
    .bind(args.photo.id)
    .bind(args.derivative.id)
    .bind(completion_seq)
    .fetch_one(&mut **tx)
    .await?;

    link_photos(tx, args).await?;
    write_document(tx, account_id, args).await?;
    let created = items::confirm(tx, account_id, &args.items).await?;
    items::record_wears(
        tx,
        account_id,
        &args.items,
        args.completion_id,
        args.local_date,
    )
    .await?;
    super::enqueue_illustrations(tx, account_id, &created).await?;
    close_active_challenge(tx, account_id).await?;

    Ok(completion)
}

async fn link_photos(tx: &mut Tx<'_>, args: &Args) -> Result<(), Error> {
    sqlx::query(
        "insert into completion_photo (completion_id, photo_id, role) values ($1, $2, 'primary')",
    )
    .bind(args.completion_id)
    .bind(args.photo.id)
    .execute(&mut **tx)
    .await?;

    for layer in &args.layer_photo_ids {
        sqlx::query(
            "insert into completion_photo (completion_id, photo_id, role)
             select $1, $2, 'layer' where exists (select 1 from photo where id = $2)
             on conflict (completion_id, photo_id) do nothing",
        )
        .bind(args.completion_id)
        .bind(layer)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

async fn write_document(tx: &mut Tx<'_>, account_id: Uuid, args: &Args) -> Result<(), Error> {
    let seq = super::next(tx, account_id).await?;
    sqlx::query(
        "insert into canvas_document
             (id, account_id, completion_id, derivative_id, schema_version, media_object_id,
              history_media_object_id, history_step_count, change_seq)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(args.document.id)
    .bind(account_id)
    .bind(args.completion_id)
    .bind(args.derivative.id)
    .bind(args.document.schema_version)
    .bind(args.document.media_object_id)
    .bind(args.document.history_media_object_id)
    .bind(args.document.history_step_count)
    .bind(seq)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn close_active_challenge(tx: &mut Tx<'_>, account_id: Uuid) -> Result<(), Error> {
    let live: Option<(Uuid,)> = sqlx::query_as(
        "select id from active_challenge where account_id = $1 and deleted_at is null",
    )
    .bind(account_id)
    .fetch_optional(&mut **tx)
    .await?;

    let Some((id,)) = live else {
        return Ok(());
    };

    let seq = super::next(tx, account_id).await?;
    sqlx::query("update active_challenge set deleted_at = now(), change_seq = $2 where id = $1")
        .bind(id)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

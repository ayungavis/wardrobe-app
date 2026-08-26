pub mod merge;

use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::error::Error;

/// # Errors
///
/// Returns any database error unchanged.
pub async fn anonymous_account(
    tx: &mut Transaction<'_, Postgres>,
    device_id: Uuid,
) -> Result<Uuid, Error> {
    if let Some((account_id,)) = existing_device(tx, device_id).await? {
        return Ok(account_id);
    }

    let account_id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(account_id)
        .execute(&mut **tx)
        .await?;
    register_device(tx, device_id, account_id).await?;
    Ok(account_id)
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn link_apple(
    tx: &mut Transaction<'_, Postgres>,
    subject: &str,
    device_id: Uuid,
) -> Result<Uuid, Error> {
    let existing: Option<(Uuid,)> =
        sqlx::query_as("select id from account where apple_subject = $1 and deleted_at is null")
            .bind(subject)
            .fetch_optional(&mut **tx)
            .await?;
    let device_account = existing_device(tx, device_id).await?.map(|(id,)| id);

    match (existing, device_account) {
        (Some((account_id,)), Some(device)) if device == account_id => Ok(account_id),

        (Some((account_id,)), Some(device)) => {
            merge::into(tx, account_id, device).await?;
            register_device(tx, device_id, account_id).await?;
            Ok(account_id)
        }
        (Some((account_id,)), None) => {
            register_device(tx, device_id, account_id).await?;
            Ok(account_id)
        }

        (None, Some(account_id)) => {
            sqlx::query("update account set apple_subject = $2 where id = $1")
                .bind(account_id)
                .bind(subject)
                .execute(&mut **tx)
                .await?;
            Ok(account_id)
        }
        (None, None) => {
            let account_id = Uuid::now_v7();
            sqlx::query("insert into account (id, apple_subject) values ($1, $2)")
                .bind(account_id)
                .bind(subject)
                .execute(&mut **tx)
                .await?;
            register_device(tx, device_id, account_id).await?;
            Ok(account_id)
        }
    }
}

async fn existing_device(
    tx: &mut Transaction<'_, Postgres>,
    device_id: Uuid,
) -> Result<Option<(Uuid,)>, Error> {
    sqlx::query_as("select account_id from account_device where anonymous_id = $1")
        .bind(device_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(Error::from)
}

async fn register_device(
    tx: &mut Transaction<'_, Postgres>,
    device_id: Uuid,
    account_id: Uuid,
) -> Result<(), Error> {
    sqlx::query(
        "insert into account_device (anonymous_id, account_id, last_seen_at)
         values ($1, $2, now())
         on conflict (anonymous_id) do update
            set account_id = excluded.account_id, last_seen_at = now()",
    )
    .bind(device_id)
    .bind(account_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

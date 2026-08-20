use chrono::{DateTime, Duration, Utc};
use sqlx::{PgConnection, Postgres, Transaction};
use uuid::Uuid;

use crate::auth::hash_token;
use crate::error::Error;

pub const ACCESS_LIFETIME_DAYS: i64 = 30;
pub const REFRESH_LIFETIME_DAYS: i64 = 180;

pub struct Issued {
    pub account_id: Uuid,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: DateTime<Utc>,
    pub refresh_expires_at: DateTime<Utc>,
}

/// # Panics
///
/// Panics when the operating system cannot supply randomness, which leaves no
/// safe way to mint a session token.
#[must_use]
pub fn secret() -> String {
    let mut bytes = [0_u8; 32];
    // The OS CSPRNG directly: a session token has no business depending on a
    // userspace generator's seeding.
    getrandom::fill(&mut bytes).expect("the operating system must provide randomness");
    bytes
        .iter()
        .fold(String::with_capacity(64), |mut out, byte| {
            use std::fmt::Write;
            let _ = write!(out, "{byte:02x}");
            out
        })
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn issue(
    conn: &mut PgConnection,
    account_id: Uuid,
    device_id: Uuid,
) -> Result<Issued, Error> {
    let id = Uuid::now_v7();
    let access_token = secret();
    let refresh_token = secret();
    let expires_at = Utc::now() + Duration::days(ACCESS_LIFETIME_DAYS);
    let refresh_expires_at = Utc::now() + Duration::days(REFRESH_LIFETIME_DAYS);

    sqlx::query(
        "insert into session
             (id, account_id, device_id, family_id, token_hash, refresh_token_hash,
              expires_at, refresh_expires_at)
         values ($1, $2, $3, $1, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(account_id)
    .bind(device_id)
    .bind(hash_token(&access_token))
    .bind(hash_token(&refresh_token))
    .bind(expires_at)
    .bind(refresh_expires_at)
    .execute(&mut *conn)
    .await?;

    Ok(Issued {
        account_id,
        access_token,
        refresh_token,
        expires_at,
        refresh_expires_at,
    })
}

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
/// Returns [`Error::Conflict`] when this device already holds data for a
/// different account, which needs a merge rather than a link.
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
        // Already this account's device.
        (Some((account_id,)), Some(device)) if device == account_id => Ok(account_id),

        // Second device. Moving the device row is the whole of it while the
        // anonymous account holds nothing; anything else is a merge (T06b).
        (Some((account_id,)), Some(device)) => {
            if holds_data(tx, device).await? {
                return Err(Error::Conflict);
            }
            register_device(tx, device_id, account_id).await?;
            sqlx::query("delete from account where id = $1")
                .bind(device)
                .execute(&mut **tx)
                .await?;
            Ok(account_id)
        }
        (Some((account_id,)), None) => {
            register_device(tx, device_id, account_id).await?;
            Ok(account_id)
        }

        // First sign-in: the anonymous account becomes the Apple account, so no
        // row moves and no change_seq needs renumbering.
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

async fn holds_data(tx: &mut Transaction<'_, Postgres>, account_id: Uuid) -> Result<bool, Error> {
    let (any,): (bool,) = sqlx::query_as(
        "select exists (select 1 from wardrobe_item where account_id = $1)
             or exists (select 1 from photo           where account_id = $1)
             or exists (select 1 from challenge_completion where account_id = $1)
             or exists (select 1 from wear_record     where account_id = $1)
             or exists (select 1 from active_challenge where account_id = $1)
             or exists (select 1 from account_preference where account_id = $1)",
    )
    .bind(account_id)
    .fetch_one(&mut **tx)
    .await?;
    Ok(any)
}

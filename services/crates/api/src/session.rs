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
    write_session(conn, account_id, Some(device_id), None).await
}

async fn issue_in_family(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    device_id: Option<Uuid>,
    family_id: Uuid,
) -> Result<Issued, Error> {
    write_session(tx, account_id, device_id, Some(family_id)).await
}

async fn write_session(
    conn: &mut PgConnection,
    account_id: Uuid,
    device_id: Option<Uuid>,
    family_id: Option<Uuid>,
) -> Result<Issued, Error> {
    let id = Uuid::now_v7();
    let family_id = family_id.unwrap_or(id);
    let access_token = secret();
    let refresh_token = secret();
    let expires_at = Utc::now() + Duration::days(ACCESS_LIFETIME_DAYS);
    let refresh_expires_at = Utc::now() + Duration::days(REFRESH_LIFETIME_DAYS);

    sqlx::query(
        "insert into session
             (id, account_id, device_id, family_id, token_hash, refresh_token_hash,
              expires_at, refresh_expires_at)
         values ($1, $2, $3, $8, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(account_id)
    .bind(device_id)
    .bind(hash_token(&access_token))
    .bind(hash_token(&refresh_token))
    .bind(expires_at)
    .bind(refresh_expires_at)
    .bind(family_id)
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

#[derive(sqlx::FromRow)]
struct RefreshRow {
    id: Uuid,
    account_id: Uuid,
    device_id: Option<Uuid>,
    family_id: Uuid,
    rotated_at: Option<DateTime<Utc>>,
    revoked_at: Option<DateTime<Utc>>,
    refresh_expires_at: Option<DateTime<Utc>>,
}

pub enum Refreshed {
    Rotated(Issued),
    Replayed,
    Unknown,
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn rotate(
    tx: &mut Transaction<'_, Postgres>,
    refresh_token: &str,
) -> Result<Refreshed, Error> {
    let row: Option<RefreshRow> = sqlx::query_as(
        "select id, account_id, device_id, family_id, rotated_at, revoked_at, refresh_expires_at
           from session
          where refresh_token_hash = $1
          for update",
    )
    .bind(hash_token(refresh_token))
    .fetch_optional(&mut **tx)
    .await?;

    let Some(row) = row else {
        return Ok(Refreshed::Unknown);
    };

    if row.rotated_at.is_some() {
        revoke_family(tx, row.family_id).await?;
        return Ok(Refreshed::Replayed);
    }
    if row.revoked_at.is_some() || row.refresh_expires_at.is_none_or(|at| at <= Utc::now()) {
        return Ok(Refreshed::Unknown);
    }

    sqlx::query("update session set rotated_at = now(), revoked_at = now() where id = $1")
        .bind(row.id)
        .execute(&mut **tx)
        .await?;

    let issued = issue_in_family(tx, row.account_id, row.device_id, row.family_id).await?;
    Ok(Refreshed::Rotated(issued))
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn revoke_family(
    tx: &mut Transaction<'_, Postgres>,
    family_id: Uuid,
) -> Result<(), Error> {
    sqlx::query(
        "update session set revoked_at = now() where family_id = $1 and revoked_at is null",
    )
    .bind(family_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

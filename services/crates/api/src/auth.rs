pub mod apple;

use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;
use crate::state::AppState;

#[derive(Debug, Clone, Copy)]
pub struct Session {
    pub account_id: Uuid,
    pub session_id: Uuid,
}

impl FromRequestParts<AppState> for Session {
    type Rejection = Error;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = bearer(parts).ok_or(Error::Unauthenticated)?;
        resolve(&state.pool, &token)
            .await?
            .ok_or(Error::Unauthenticated)
    }
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn resolve(pool: &PgPool, token: &str) -> Result<Option<Session>, Error> {
    let row: Option<(Uuid, Uuid)> = sqlx::query_as(
        "select id, account_id
           from session
          where token_hash = $1
            and revoked_at is null
            and expires_at > now()",
    )
    .bind(hash_token(token))
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|(session_id, account_id)| Session {
        account_id,
        session_id,
    }))
}

#[must_use]
pub fn hash_token(token: &str) -> Vec<u8> {
    Sha256::digest(token.as_bytes()).to_vec()
}

fn bearer(parts: &Parts) -> Option<String> {
    let value = parts.headers.get(AUTHORIZATION)?.to_str().ok()?;
    let (scheme, token) = value.split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("bearer") || token.trim().is_empty() {
        return None;
    }
    Some(token.trim().to_owned())
}

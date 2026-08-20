use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::account;
use crate::auth::Session;
use crate::auth::apple::AppleError;
use crate::error::Error;
use crate::session::{self, Issued, Refreshed};
use crate::state::AppState;

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AnonymousRequest {
    /// The UUID the client holds in its Keychain.
    pub device_id: Uuid,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RefreshRequest {
    /// The refresh token from the previous session response.
    pub refresh_token: String,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AppleRequest {
    pub device_id: Uuid,
    /// The identity token Apple returned to the client.
    pub identity_token: String,
    /// The raw nonce whose SHA-256 the client sent to Apple.
    pub nonce: String,
}

/// A newly issued session.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SessionResponse {
    pub account_id: Uuid,
    /// Returned exactly once; only its hash is stored.
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: DateTime<Utc>,
    pub refresh_expires_at: DateTime<Utc>,
}

impl From<Issued> for SessionResponse {
    fn from(issued: Issued) -> Self {
        Self {
            account_id: issued.account_id,
            access_token: issued.access_token,
            refresh_token: issued.refresh_token,
            expires_at: issued.expires_at,
            refresh_expires_at: issued.refresh_expires_at,
        }
    }
}

impl From<AppleError> for Error {
    fn from(error: AppleError) -> Self {
        match error {
            AppleError::NotConfigured | AppleError::KeysUnavailable => Self::Unavailable,
            AppleError::Rejected | AppleError::UnknownKey => Self::Unauthenticated,
        }
    }
}

/// Starts or resumes an anonymous account for a device.
#[utoipa::path(
    post,
    path = "/v1/sessions/anonymous",
    tag = "session",
    request_body = AnonymousRequest,
    responses(
        (status = 200, description = "A session for the device's anonymous account", body = SessionResponse),
        (status = 400, description = "The device id is not a UUID", body = crate::error::ErrorBody),
    )
)]
pub async fn anonymous(
    State(state): State<AppState>,
    Json(request): Json<AnonymousRequest>,
) -> Result<Json<SessionResponse>, Error> {
    let mut tx = state.pool.begin().await?;
    let account_id = account::anonymous_account(&mut tx, request.device_id).await?;
    let issued = session::issue(&mut tx, account_id, request.device_id).await?;
    tx.commit().await?;

    Ok(Json(issued.into()))
}

/// Verifies an Apple identity token and links it to this device's account.
#[utoipa::path(
    post,
    path = "/v1/sessions/apple",
    tag = "session",
    request_body = AppleRequest,
    responses(
        (status = 200, description = "A session for the Apple-backed account", body = SessionResponse),
        (status = 401, description = "The identity token did not verify", body = crate::error::ErrorBody),
        (status = 409, description = "This device holds data for another account", body = crate::error::ErrorBody),
        (status = 503, description = "Apple sign-in is not configured or Apple is unreachable", body = crate::error::ErrorBody),
    )
)]
pub async fn apple(
    State(state): State<AppState>,
    Json(request): Json<AppleRequest>,
) -> Result<Json<SessionResponse>, Error> {
    let identity = state
        .apple
        .verify(&request.identity_token, &request.nonce)
        .await?;

    let mut tx = state.pool.begin().await?;
    let account_id = account::link_apple(&mut tx, &identity.subject, request.device_id).await?;
    let issued = session::issue(&mut tx, account_id, request.device_id).await?;
    tx.commit().await?;

    Ok(Json(issued.into()))
}

/// Exchanges a refresh token for a new pair and retires the old one.
#[utoipa::path(
    post,
    path = "/v1/sessions/refresh",
    tag = "session",
    request_body = RefreshRequest,
    responses(
        (status = 200, description = "A rotated session", body = SessionResponse),
        (status = 401, description = "Unknown, expired, revoked, or already-used refresh token", body = crate::error::ErrorBody),
    )
)]
pub async fn refresh(
    State(state): State<AppState>,
    Json(request): Json<RefreshRequest>,
) -> Result<Json<SessionResponse>, Error> {
    let mut tx = state.pool.begin().await?;
    let outcome = session::rotate(&mut tx, &request.refresh_token).await?;
    tx.commit().await?;

    match outcome {
        Refreshed::Rotated(issued) => Ok(Json(issued.into())),
        Refreshed::Replayed => {
            tracing::warn!("a rotated refresh token was replayed; its session family was revoked");
            Err(Error::Unauthenticated)
        }
        Refreshed::Unknown => Err(Error::Unauthenticated),
    }
}

/// Revokes every session in this device's family.
#[utoipa::path(
    delete,
    path = "/v1/sessions/current",
    tag = "session",
    security(("session" = [])),
    responses(
        (status = 204, description = "The family is revoked; server data is untouched"),
        (status = 401, description = "Missing or unusable token", body = crate::error::ErrorBody),
    )
)]
pub async fn sign_out(
    State(state): State<AppState>,
    session: Session,
) -> Result<StatusCode, Error> {
    sqlx::query(
        "update session
            set revoked_at = now()
          where family_id = (select family_id from session where id = $1)
            and revoked_at is null",
    )
    .bind(session.session_id)
    .execute(&state.pool)
    .await?;

    Ok(StatusCode::NO_CONTENT)
}

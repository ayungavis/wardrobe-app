use axum::Json;
use axum::extract::{Path, State};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::auth::Session;
use crate::error::Error;
use crate::media::{self, Granted, Reservation};
use crate::state::AppState;

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ReserveRequest {
    /// The client's own id for this object, reused on a retry.
    pub media_id: Uuid,
    /// One of original, derivative, cutout, illustration, document, history.
    pub kind: String,
    pub content_type: String,
    pub byte_size: Option<i64>,
}

/// A short-lived grant to move bytes, never an identity to store.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct GrantResponse {
    pub media_id: Uuid,
    pub url: String,
    pub expires_at: DateTime<Utc>,
    pub byte_size: Option<i64>,
}

impl From<Granted> for GrantResponse {
    fn from(granted: Granted) -> Self {
        Self {
            media_id: granted.media_id,
            url: granted.url,
            expires_at: granted.expires_at,
            byte_size: granted.byte_size,
        }
    }
}

/// Registers an object and returns a signed URL to upload it.
#[utoipa::path(
    post,
    path = "/v1/media",
    tag = "media",
    security(("session" = [])),
    request_body = ReserveRequest,
    responses(
        (status = 200, description = "A signed upload URL", body = GrantResponse),
        (status = 400, description = "Unknown kind or unusable metadata", body = crate::error::ErrorBody),
        (status = 401, description = "Missing or unusable token", body = crate::error::ErrorBody),
        (status = 409, description = "That id belongs to another account", body = crate::error::ErrorBody),
        (status = 503, description = "Object storage is not configured", body = crate::error::ErrorBody),
    )
)]
pub async fn reserve(
    State(state): State<AppState>,
    session: Session,
    Json(request): Json<ReserveRequest>,
) -> Result<Json<GrantResponse>, Error> {
    let storage = state.storage.as_ref().ok_or(Error::Unavailable)?;
    let granted = media::reserve(
        &state.pool,
        storage,
        session.account_id,
        &Reservation {
            media_id: request.media_id,
            kind: request.kind,
            content_type: request.content_type,
            byte_size: request.byte_size,
        },
    )
    .await?;

    Ok(Json(granted.into()))
}

/// Returns a signed URL to download an object whose bytes have arrived.
#[utoipa::path(
    get,
    path = "/v1/media/{id}",
    tag = "media",
    security(("session" = [])),
    params(("id" = Uuid, Path, description = "The media id")),
    responses(
        (status = 200, description = "A signed download URL", body = GrantResponse),
        (status = 401, description = "Missing or unusable token", body = crate::error::ErrorBody),
        (status = 404, description = "No such object, or its bytes never arrived", body = crate::error::ErrorBody),
        (status = 503, description = "Object storage is not configured", body = crate::error::ErrorBody),
    )
)]
pub async fn download(
    State(state): State<AppState>,
    session: Session,
    Path(id): Path<Uuid>,
) -> Result<Json<GrantResponse>, Error> {
    let storage = state.storage.as_ref().ok_or(Error::Unavailable)?;
    let granted = media::download(&state.pool, storage, session.account_id, id).await?;

    Ok(Json(granted.into()))
}

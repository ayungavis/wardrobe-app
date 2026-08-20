use axum::Json;
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::auth::Session;

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct WhoAmI {
    /// The account this session belongs to.
    pub account_id: Uuid,
    pub session_id: Uuid,
}

/// Confirms which account a session token belongs to.
#[utoipa::path(
    get,
    path = "/v1/whoami",
    tag = "session",
    security(("session" = [])),
    responses(
        (status = 200, description = "The session is valid", body = WhoAmI),
        (status = 401, description = "Missing, malformed, unknown, expired, or revoked token",
         body = crate::error::ErrorBody),
    )
)]
pub async fn whoami(session: Session) -> Json<WhoAmI> {
    Json(WhoAmI {
        account_id: session.account_id,
        session_id: session.session_id,
    })
}

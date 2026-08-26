use axum::extract::State;
use axum::http::StatusCode;

use crate::auth::Session;
use crate::deletion;
use crate::error::Error;
use crate::state::AppState;

/// Removes the account: its rows, its objects, and every session it owns.
#[utoipa::path(
    delete,
    path = "/v1/users/me",
    tag = "account",
    security(("session" = [])),
    responses(
        (status = 204, description = "Rows and objects are gone; nothing remains to retry"),
        (status = 401, description = "Missing or unusable token", body = crate::error::ErrorBody),
        (status = 503, description = "Objects remain and could not be removed; retry", body = crate::error::ErrorBody),
    )
)]
pub async fn delete_me(
    State(state): State<AppState>,
    session: Session,
) -> Result<StatusCode, Error> {
    deletion::account(&state.pool, state.storage.as_deref(), session.account_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

use axum::Json;
use axum::extract::{Query, State};
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};

use crate::auth::Session;
use crate::changes::{self, Change};
use crate::error::Error;
use crate::state::AppState;

#[derive(Debug, Deserialize, IntoParams)]
#[serde(rename_all = "camelCase")]
#[into_params(parameter_in = Query)]
pub struct Cursor {
    /// The last `changeSeq` you received; omit to start from the beginning.
    pub since: Option<i64>,
    /// How many records to return, clamped to 1000.
    pub limit: Option<i64>,
}

/// One page of the change feed, oldest position first.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ChangesResponse {
    pub changes: Vec<Change>,
    /// Pass this back as `since`; it never moves past a record this page omitted.
    pub next_since: i64,
}

/// Returns every record written after a cursor position, deletions included.
#[utoipa::path(
    get,
    path = "/v1/changes",
    tag = "sync",
    security(("session" = [])),
    params(Cursor),
    responses(
        (status = 200, description = "One page of changes", body = ChangesResponse),
        (status = 401, description = "Missing or unusable token", body = crate::error::ErrorBody),
    )
)]
pub async fn changes(
    State(state): State<AppState>,
    session: Session,
    Query(cursor): Query<Cursor>,
) -> Result<Json<ChangesResponse>, Error> {
    let (changes, next_since) = changes::since(
        &state.pool,
        session.account_id,
        cursor.since.unwrap_or(0),
        cursor.limit.unwrap_or(changes::DEFAULT_LIMIT),
    )
    .await?;

    Ok(Json(ChangesResponse {
        changes,
        next_since,
    }))
}

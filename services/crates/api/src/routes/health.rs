use axum::Json;
use axum::extract::State;
use serde::Serialize;
use utoipa::ToSchema;

use crate::error::Error;
use crate::state::AppState;

#[derive(Debug, Serialize, ToSchema)]
pub struct Health {
    /// `ok` when the process is up and the database answers.
    #[schema(example = "ok")]
    pub status: String,
}

/// Liveness and readiness in one.
///
/// It deliberately touches `PostgreSQL`: a health check that does not would only
/// report that this process is running, which is the least useful thing to know
/// about a service whose entire job is reading and writing a database.
#[utoipa::path(
    get,
    path = "/health",
    tag = "health",
    responses(
        (status = 200, description = "The service and its database are reachable", body = Health),
        (status = 503, description = "The database is unreachable", body = crate::error::ErrorBody),
    )
)]
pub async fn health(State(state): State<AppState>) -> Result<Json<Health>, Error> {
    sqlx::query_scalar::<_, i32>("select 1")
        .fetch_one(&state.pool)
        .await
        .map_err(|source| {
            tracing::warn!(error = %source, "health check could not reach the database");
            Error::Unavailable
        })?;

    Ok(Json(Health {
        status: "ok".to_owned(),
    }))
}

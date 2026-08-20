use axum::Json;
use axum::body::Bytes;
use axum::extract::State;
use axum::extract::rejection::BytesRejection;
use serde::{Deserialize, Serialize};
use tracing::Instrument;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::auth::Session;
use crate::error::{Error, ErrorDetail};
use crate::state::AppState;
use crate::sync;

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SyncRequest {
    pub mutations: Vec<MutationRequest>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MutationRequest {
    /// The client's own id for this mutation, echoed back in its result.
    pub id: Uuid,
    /// Which mutation to run, such as `deleteItem`.
    pub name: String,
    // ponytail: the payload is untyped here because a typed enum would make one
    // malformed `args` fail the whole batch. Give each mutation a schema of its
    // own once there are enough for a client generator to care.
    /// Arguments for this mutation.
    #[schema(value_type = Object)]
    pub args: serde_json::Value,
}

/// The outcome of every mutation in the batch, in the order they were sent.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SyncResponse {
    pub results: Vec<MutationResult>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MutationResult {
    pub id: Uuid,
    pub name: String,
    #[serde(flatten)]
    pub outcome: Outcome,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum Outcome {
    Applied {
        /// The record as it now stands, which a replay returns unchanged.
        #[schema(value_type = Object)]
        record: serde_json::Value,
    },
    Failed {
        /// This mutation alone failed; its neighbours were still applied.
        error: ErrorDetail,
    },
}

/// Applies a batch of named mutations, each in its own transaction.
#[utoipa::path(
    post,
    path = "/v1/sync",
    tag = "sync",
    security(("session" = [])),
    request_body = SyncRequest,
    responses(
        (status = 200, description = "Every mutation reported individually", body = SyncResponse),
        (status = 400, description = "The envelope itself could not be read", body = crate::error::ErrorBody),
        (status = 401, description = "Missing or unusable token", body = crate::error::ErrorBody),
        (status = 413, description = "More than 100 mutations, or a body past 1 MB", body = crate::error::ErrorBody),
    )
)]
pub async fn sync(
    State(state): State<AppState>,
    session: Session,
    body: Result<Bytes, BytesRejection>,
) -> Result<Json<SyncResponse>, Error> {
    let body = body.map_err(|_| Error::TooLarge)?;
    if body.len() > sync::MAX_BODY_BYTES {
        return Err(Error::TooLarge);
    }
    let request: SyncRequest = serde_json::from_slice(&body).map_err(|_| Error::BadRequest)?;
    if request.mutations.len() > sync::MAX_MUTATIONS {
        return Err(Error::TooLarge);
    }

    let mut results = Vec::with_capacity(request.mutations.len());
    for mutation in request.mutations {
        let MutationRequest { id, name, args } = mutation;
        let span = tracing::info_span!("mutation", name = name.as_str());
        let outcome = sync::apply(&state.pool, session.account_id, &name, args)
            .instrument(span)
            .await;
        results.push(MutationResult {
            id,
            name,
            outcome: match outcome {
                Ok(record) => Outcome::Applied { record },
                Err(failure) => Outcome::Failed {
                    error: failure.detail(),
                },
            },
        });
    }

    Ok(Json(SyncResponse { results }))
}

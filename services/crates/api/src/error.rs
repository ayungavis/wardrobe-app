use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use utoipa::ToSchema;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("the request is malformed")]
    BadRequest,
    #[error("authentication required")]
    Unauthenticated,
    #[error("the request conflicts with stored state")]
    Conflict,
    #[error("service unavailable")]
    Unavailable,
    #[error("internal error")]
    Internal(#[from] sqlx::Error),
}

impl Error {
    fn status(&self) -> StatusCode {
        match self {
            Self::BadRequest => StatusCode::BAD_REQUEST,
            Self::Unauthenticated => StatusCode::UNAUTHORIZED,
            Self::Conflict => StatusCode::CONFLICT,
            Self::Unavailable => StatusCode::SERVICE_UNAVAILABLE,
            Self::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    fn code(&self) -> &'static str {
        match self {
            Self::BadRequest => "bad_request",
            Self::Unauthenticated => "unauthenticated",
            Self::Conflict => "conflict",
            Self::Unavailable => "unavailable",
            Self::Internal(_) => "internal",
        }
    }

    fn message(&self) -> &'static str {
        match self {
            Self::BadRequest => "The request could not be understood.",
            Self::Unauthenticated => "Authentication is required for this request.",
            Self::Conflict => {
                "This device already holds data for a different account. Sign in on a fresh install, or contact support to merge them."
            }
            Self::Unavailable => "The service is temporarily unavailable. Try again shortly.",
            Self::Internal(_) => "Something went wrong on our side.",
        }
    }
}

/// The single error shape every endpoint returns.
#[derive(Debug, Serialize, ToSchema)]
pub struct ErrorBody {
    pub error: ErrorDetail,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ErrorDetail {
    /// Stable, matchable identifier — part of the contract.
    #[schema(example = "unauthenticated")]
    pub code: String,
    /// Human-readable and safe to display.
    #[schema(example = "Authentication is required for this request.")]
    pub message: String,
}

impl IntoResponse for Error {
    fn into_response(self) -> Response {
        if let Self::Internal(source) = &self {
            // A Postgres message quotes the failing row, so it can carry item
            // names and other user content that §18.12 forbids in a log. Only
            // the classification, the SQLSTATE, and the constraint name — which
            // name schema objects, never values — are safe to record.
            let facts = wardrobe_db::error_facts(source);
            tracing::error!(
                error.kind = facts.code,
                error.sqlstate = facts.sqlstate,
                error.constraint = facts.constraint,
                "internal error"
            );
        }

        let body = ErrorBody {
            error: ErrorDetail {
                code: self.code().to_owned(),
                message: self.message().to_owned(),
            },
        };
        (self.status(), Json(body)).into_response()
    }
}

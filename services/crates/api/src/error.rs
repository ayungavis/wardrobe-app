use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use utoipa::ToSchema;

/// Every failure the API can return.
///
/// One enum and one `IntoResponse` means the status mapping lives in a single
/// place: once a variant has a status, every handler is consistent without
/// having to remember anything.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("authentication required")]
    Unauthenticated,
    #[error("service unavailable")]
    Unavailable,
    /// The source is logged, never returned: it can quote SQL, object keys, or
    /// provider payloads, none of which may leave the process (PRD §18.12).
    #[error("internal error")]
    Internal(#[from] sqlx::Error),
}

impl Error {
    fn status(&self) -> StatusCode {
        match self {
            Self::Unauthenticated => StatusCode::UNAUTHORIZED,
            Self::Unavailable => StatusCode::SERVICE_UNAVAILABLE,
            Self::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    /// A stable identifier clients may branch on. Unlike the message, this is
    /// part of the contract and does not change with wording.
    fn code(&self) -> &'static str {
        match self {
            Self::Unauthenticated => "unauthenticated",
            Self::Unavailable => "unavailable",
            Self::Internal(_) => "internal",
        }
    }

    /// Safe to show a user. Deliberately not derived from the source error.
    fn message(&self) -> &'static str {
        match self {
            Self::Unauthenticated => "Authentication is required for this request.",
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
            tracing::error!(error = %source, "internal error");
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

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
    #[error("the referenced record does not exist")]
    NotFound,
    #[error("the request is too large")]
    TooLarge,
    #[error("too many requests")]
    TooManyRequests,
    #[error("service unavailable")]
    Unavailable,
    #[error("internal error")]
    Internal(#[from] sqlx::Error),
    #[error("the merge left rows behind")]
    MergeIncomplete,
}

impl Error {
    fn status(&self) -> StatusCode {
        match self {
            Self::BadRequest => StatusCode::BAD_REQUEST,
            Self::Unauthenticated => StatusCode::UNAUTHORIZED,
            Self::Conflict => StatusCode::CONFLICT,
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::TooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            Self::TooManyRequests => StatusCode::TOO_MANY_REQUESTS,
            Self::Unavailable => StatusCode::SERVICE_UNAVAILABLE,
            Self::Internal(_) | Self::MergeIncomplete => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    fn code(&self) -> &'static str {
        match self {
            Self::BadRequest => "bad_request",
            Self::Unauthenticated => "unauthenticated",
            Self::Conflict => "conflict",
            Self::NotFound => "not_found",
            Self::TooLarge => "payload_too_large",
            Self::TooManyRequests => "too_many_requests",
            Self::Unavailable => "unavailable",
            Self::Internal(_) | Self::MergeIncomplete => "internal",
        }
    }

    fn message(&self) -> &'static str {
        match self {
            Self::BadRequest => "The request could not be understood.",
            Self::Unauthenticated => "Authentication is required for this request.",
            Self::Conflict => "That change conflicts with data already stored for this account.",
            Self::NotFound => "That record does not exist.",
            Self::TooLarge => {
                "The request is larger than this endpoint accepts. Send fewer changes at a time."
            }
            Self::TooManyRequests => "Too many requests. Wait a moment and try again.",
            Self::Unavailable => "The service is temporarily unavailable. Try again shortly.",
            Self::Internal(_) | Self::MergeIncomplete => "Something went wrong on our side.",
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

impl Error {
    #[must_use]
    pub fn body(&self) -> ErrorBody {
        ErrorBody {
            error: self.detail(),
        }
    }

    #[must_use]
    pub fn detail(&self) -> ErrorDetail {
        match self {
            Self::Internal(source) => {
                let facts = wardrobe_db::error_facts(source);
                tracing::error!(
                    error.kind = facts.code,
                    error.sqlstate = facts.sqlstate,
                    error.constraint = facts.constraint,
                    "internal error"
                );
            }
            Self::MergeIncomplete => {
                tracing::error!(error.code = self.code(), "request refused");
            }
            Self::TooManyRequests => {}
            _ => {
                tracing::warn!(error.code = self.code(), "request refused");
            }
        }

        ErrorDetail {
            code: self.code().to_owned(),
            message: self.message().to_owned(),
        }
    }
}

impl IntoResponse for Error {
    fn into_response(self) -> Response {
        let status = self.status();
        (
            status,
            Json(ErrorBody {
                error: self.detail(),
            }),
        )
            .into_response()
    }
}

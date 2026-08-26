pub mod account;
pub mod auth;
pub mod changes;
pub mod config;
pub mod deck;
pub mod deletion;
pub mod error;
pub mod limit;
pub mod media;
pub mod openapi;
pub mod routes;
pub mod session;
pub mod state;
pub mod sync;

use std::sync::Arc;

use axum::Router;
use sqlx::PgPool;
use tower_http::ServiceBuilderExt;
use tower_http::request_id::MakeRequestUuid;
use tower_http::trace::{DefaultOnResponse, TraceLayer};
use tracing::Level;
use utoipa::OpenApi;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use utoipa_swagger_ui::SwaggerUi;

use crate::openapi::ApiDoc;
use crate::state::AppState;

fn request_span(request: &axum::http::Request<axum::body::Body>) -> tracing::Span {
    let request_id = request
        .headers()
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("-");
    tracing::info_span!(
        "http",
        request_id = %request_id,
        method = %request.method(),
        path = %request.uri().path(),
    )
}

fn api_router() -> OpenApiRouter<AppState> {
    unauthenticated_router().merge(authenticated_router())
}

fn unauthenticated_router() -> OpenApiRouter<AppState> {
    OpenApiRouter::with_openapi(ApiDoc::openapi())
        .routes(routes!(routes::health::health))
        .routes(routes!(routes::sessions::anonymous))
        .routes(routes!(routes::sessions::apple))
        .routes(routes!(routes::sessions::refresh))
}

fn authenticated_router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(routes::whoami::whoami))
        .routes(routes!(routes::sessions::sign_out))
        .routes(routes!(routes::sync::sync))
        .routes(routes!(routes::changes::changes))
        .routes(routes!(routes::deck::deck))
        .routes(routes!(routes::media::reserve))
        .routes(routes!(routes::media::download))
        .routes(routes!(routes::users::delete_me))
}

pub const MAX_BODY_BYTES: usize = 1024 * 1024;
pub const REQUEST_TIMEOUT_SECONDS: u64 = 30;

// ponytail: the limiter counts in this process, so two instances mean twice the
// limit. Redis is the approved shared counter once a measured threshold says so.
// Starting values only; every one of them waits on pilot load to be validated.
const REQUESTS_PER_SECOND: u64 = 1;
const AUTHENTICATED_BURST: u32 = 120;
const ANONYMOUS_PER_SECOND: u64 = 6;
const ANONYMOUS_BURST: u32 = 10;

pub fn app(
    pool: PgPool,
    apple: Arc<auth::apple::Verifier>,
    storage: Option<Arc<wardrobe_storage::Storage>>,
) -> Router {
    app_with(pool, apple, storage, limit::DEFAULT_TRUSTED_HOPS, true)
}

pub fn app_with(
    pool: PgPool,
    apple: Arc<auth::apple::Verifier>,
    storage: Option<Arc<wardrobe_storage::Storage>>,
    trusted_hops: usize,
    serve_docs: bool,
) -> Router {
    let state = AppState::new(pool, apple, storage);
    let (open, api) = unauthenticated_router()
        .with_state(state.clone())
        .split_for_parts();
    let (closed, _) = authenticated_router().with_state(state).split_for_parts();

    let router = open
        .layer(limit::layer(
            ANONYMOUS_PER_SECOND,
            ANONYMOUS_BURST,
            trusted_hops,
        ))
        .merge(closed.layer(limit::layer(
            REQUESTS_PER_SECOND,
            AUTHENTICATED_BURST,
            trusted_hops,
        )));

    let observability = tower::ServiceBuilder::new()
        .set_x_request_id(MakeRequestUuid)
        .layer(sentry::integrations::tower::NewSentryLayer::new_from_top())
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(request_span)
                .on_response(DefaultOnResponse::new().level(Level::INFO)),
        )
        .propagate_x_request_id();

    let hardening = tower::ServiceBuilder::new()
        .layer(axum::extract::DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(tower_http::timeout::TimeoutLayer::with_status_code(
            axum::http::StatusCode::REQUEST_TIMEOUT,
            std::time::Duration::from_secs(REQUEST_TIMEOUT_SECONDS),
        ))
        .layer(
            tower_http::set_header::SetResponseHeaderLayer::if_not_present(
                axum::http::HeaderName::from_static("x-content-type-options"),
                axum::http::HeaderValue::from_static("nosniff"),
            ),
        );

    let router = if serve_docs {
        router.merge(SwaggerUi::new("/docs").url("/openapi.json", api))
    } else {
        router.route(
            "/openapi.json",
            axum::routing::get(move || std::future::ready(axum::Json(api.clone()))),
        )
    };

    router.layer(hardening).layer(observability)
}

#[must_use]
pub fn app_openapi() -> utoipa::openapi::OpenApi {
    api_router().split_for_parts().1
}

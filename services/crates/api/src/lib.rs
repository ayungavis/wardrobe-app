pub mod auth;
pub mod config;
pub mod error;
pub mod observability;
pub mod openapi;
pub mod routes;
pub mod state;

use axum::Router;
use sqlx::PgPool;
use tower_http::ServiceBuilderExt;
use tower_http::request_id::MakeRequestUuid;
use tower_http::trace::TraceLayer;
use utoipa::OpenApi;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use utoipa_swagger_ui::SwaggerUi;

use crate::openapi::ApiDoc;
use crate::state::AppState;

fn api_router() -> OpenApiRouter<AppState> {
    OpenApiRouter::with_openapi(ApiDoc::openapi())
        .routes(routes!(routes::health::health))
        .routes(routes!(routes::session::whoami))
}

pub fn app(pool: PgPool) -> Router {
    let (router, api) = api_router()
        .with_state(AppState::new(pool))
        .split_for_parts();

    let observability = tower::ServiceBuilder::new()
        .set_x_request_id(MakeRequestUuid)
        .layer(sentry::integrations::tower::NewSentryLayer::new_from_top())
        .layer(TraceLayer::new_for_http())
        .propagate_x_request_id();

    router
        .merge(SwaggerUi::new("/docs").url("/openapi.json", api))
        .layer(observability)
}

#[must_use]
pub fn app_openapi() -> utoipa::openapi::OpenApi {
    api_router().split_for_parts().1
}

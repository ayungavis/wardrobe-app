//! The Wardrobe HTTP API.
//!
//! The router lives here rather than in `main.rs` so tests can build the exact
//! application the binary serves, instead of a lookalike that could drift.

pub mod auth;
pub mod config;
pub mod error;
pub mod openapi;
pub mod routes;
pub mod state;

use axum::Router;
use sqlx::PgPool;
use tower_http::trace::TraceLayer;
use utoipa::OpenApi;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use utoipa_swagger_ui::SwaggerUi;

use crate::openapi::ApiDoc;
use crate::state::AppState;

/// The single place routes are registered. Both the served application and the
/// generated document come from here, so `openapi.json` cannot describe an
/// endpoint that does not exist — or miss one that does.
fn api_router() -> OpenApiRouter<AppState> {
    OpenApiRouter::with_openapi(ApiDoc::openapi())
        .routes(routes!(routes::health::health))
        .routes(routes!(routes::session::whoami))
}

/// Builds the application: routes, `OpenAPI` document, and the Swagger UI.
///
/// ponytail: the UI is unconditional while the API is private. Gate it behind
/// config when it faces the public internet.
pub fn app(pool: PgPool) -> Router {
    let (router, api) = api_router()
        .with_state(AppState::new(pool))
        .split_for_parts();

    router
        .merge(SwaggerUi::new("/docs").url("/openapi.json", api))
        .layer(TraceLayer::new_for_http())
}

/// The `OpenAPI` document on its own, for the generator and the drift test.
#[must_use]
pub fn app_openapi() -> utoipa::openapi::OpenApi {
    api_router().split_for_parts().1
}

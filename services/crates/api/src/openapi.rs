use utoipa::OpenApi;
use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
use utoipa::{Modify, openapi::OpenApi as OpenApiDoc};

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Wardrobe API",
        description = "Backend for the Wardrobe Challenge App. Session tokens are issued by the server; \
                       the client never asserts an identity of its own.",
        version = "0.1.0",
        license(name = "Proprietary"),
    ),
    modifiers(&SecurityAddon),
    tags(
        (name = "health", description = "Liveness and readiness"),
        (name = "session", description = "Session lifecycle and identity"),
    )
)]
pub struct ApiDoc;

/// # Panics
///
/// Panics if the derived document cannot be serialised, which would mean the
/// annotations themselves are malformed.
#[must_use]
pub fn document() -> String {
    let mut json = crate::app_openapi()
        .to_pretty_json()
        .expect("serialisable OpenAPI document");
    json.push('\n');
    json
}

struct SecurityAddon;

impl Modify for SecurityAddon {
    fn modify(&self, openapi: &mut OpenApiDoc) {
        let components = openapi.components.get_or_insert_with(Default::default);
        components.add_security_scheme(
            "session",
            SecurityScheme::Http(
                HttpBuilder::new()
                    .scheme(HttpAuthScheme::Bearer)
                    .description(Some(
                        "Session token from POST /v1/sessions/*. Sent as `Authorization: Bearer <token>`.",
                    ))
                    .build(),
            ),
        );
    }
}

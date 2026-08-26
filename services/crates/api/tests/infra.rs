mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call, get};

// ------------------------------------------------------------------ health

#[sqlx::test(migrations = "../../migrations")]
async fn health_reports_ok_when_the_database_answers(pool: PgPool) {
    let response = call(pool, get("/health")).await;

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(body_json(response).await["status"], "ok");
}

#[sqlx::test(migrations = "../../migrations")]
async fn health_reports_unavailable_when_the_database_is_gone(pool: PgPool) {
    pool.close().await;

    let response = call(pool, get("/health")).await;

    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(body_json(response).await["error"]["code"], "unavailable");
}

// ------------------------------------------------------------------ openapi

#[sqlx::test(migrations = "../../migrations")]
async fn the_openapi_document_is_served(pool: PgPool) {
    let response = call(pool, get("/openapi.json")).await;

    assert_eq!(response.status(), StatusCode::OK);
    let document = body_json(response).await;
    assert_eq!(document["info"]["title"], "Wardrobe API");
    assert!(document["paths"]["/health"].is_object());
}

#[test]
fn the_committed_openapi_file_matches_the_code() {
    let committed = std::fs::read_to_string("../../openapi.json")
        .expect("services/openapi.json is missing — run `make backend-openapi`");
    let generated = wardrobe_api::openapi::document();

    assert_eq!(
        committed.trim(),
        generated.trim(),
        "services/openapi.json is stale — run `make backend-openapi`"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_response_carries_a_request_id(pool: PgPool) -> sqlx::Result<()> {
    let response = call(pool.clone(), get("/health")).await;

    let id = response
        .headers()
        .get("x-request-id")
        .expect("the layer stamps one when the caller sends none");
    assert!(Uuid::parse_str(id.to_str().expect("ascii")).is_ok());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_caller_supplied_request_id_is_propagated(pool: PgPool) -> sqlx::Result<()> {
    let supplied = "0199aa11-2233-7445-8899-aabbccddeeff";
    let request = Request::builder()
        .uri("/health")
        .header("x-request-id", supplied)
        .body(Body::empty())
        .expect("request");

    let response = call(pool.clone(), request).await;

    assert_eq!(
        response.headers().get("x-request-id").unwrap(),
        supplied,
        "a client tracing one call across services must see its own id back"
    );
    Ok(())
}

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use chrono::Duration;
use serde_json::{Value, json};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;
use wardrobe_api::{MAX_BODY_BYTES, app_with, limit};

use common::{body_json, get, get_with_auth, session, storage, verifier};

fn router(pool: PgPool, serve_docs: bool) -> axum::Router {
    app_with(
        pool,
        verifier(),
        Some(storage()),
        limit::DEFAULT_TRUSTED_HOPS,
        serve_docs,
    )
}

async fn send(router: axum::Router, request: Request<Body>) -> axum::response::Response {
    router
        .oneshot(request)
        .await
        .expect("the router is infallible")
}

// -------------------------------------------------------------------- /docs

#[sqlx::test(migrations = "../../migrations")]
async fn the_api_shape_is_not_published_unless_it_is_asked_for(pool: PgPool) -> sqlx::Result<()> {
    let closed = send(router(pool.clone(), false), get("/docs")).await;
    assert_eq!(closed.status(), StatusCode::NOT_FOUND);

    let open = send(router(pool.clone(), true), get("/docs")).await;
    assert_ne!(open.status(), StatusCode::NOT_FOUND);

    for serve_docs in [false, true] {
        let contract = send(router(pool.clone(), serve_docs), get("/openapi.json")).await;
        assert_eq!(
            contract.status(),
            StatusCode::OK,
            "client generators read openapi.json, so it is served either way"
        );
    }
    Ok(())
}

// ------------------------------------------------------------------- headers

#[sqlx::test(migrations = "../../migrations")]
async fn every_response_refuses_content_type_sniffing(pool: PgPool) -> sqlx::Result<()> {
    let response = send(router(pool, true), get("/health")).await;

    assert_eq!(
        response.headers().get("x-content-type-options"),
        Some(&axum::http::HeaderValue::from_static("nosniff"))
    );
    Ok(())
}

// ---------------------------------------------------------------- body limit

#[sqlx::test(migrations = "../../migrations")]
async fn an_oversize_body_never_reaches_a_handler(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let request = Request::builder()
        .method("POST")
        .uri("/v1/sync")
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(vec![b'x'; MAX_BODY_BYTES + 1024]))
        .expect("request");

    let response = send(router(pool, false), request).await;

    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(
        body_json(response).await["error"]["code"],
        "payload_too_large"
    );
    Ok(())
}

// ------------------------------------------------------------ the envelope

#[sqlx::test(migrations = "../../migrations")]
async fn no_rejection_body_carries_anything_beyond_code_and_message(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let unknown = Uuid::now_v7();

    let rejections = vec![
        send(router(pool.clone(), false), get("/v1/whoami")).await,
        send(
            router(pool.clone(), false),
            get_with_auth("/v1/whoami", "Bearer nonsense"),
        )
        .await,
        send(
            router(pool.clone(), false),
            get_with_auth(&format!("/v1/media/{unknown}"), &format!("Bearer {token}")),
        )
        .await,
        send(router(pool.clone(), false), get("/v1/changes?since=0")).await,
    ];

    for response in rejections {
        assert!(response.status().is_client_error() || response.status().is_server_error());
        let body: Value = body_json(response).await;
        let object = body.as_object().expect("an object");
        assert_eq!(object.keys().collect::<Vec<_>>(), vec!["error"]);
        let detail = body["error"].as_object().expect("an object");
        let mut keys: Vec<&String> = detail.keys().collect();
        keys.sort();
        assert_eq!(
            keys,
            vec!["code", "message"],
            "the envelope is the contract; an extra key is a leak waiting to happen"
        );
    }
    Ok(())
}

// ------------------------------------------------------------- upload cap

#[sqlx::test(migrations = "../../migrations")]
async fn an_upload_over_its_cap_is_discarded_rather_than_stamped(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let media = Uuid::now_v7();
    let key = format!("{account}/cutout/{media}");
    let cap = usize::try_from(wardrobe_db::upload_cap("cutout")).expect("a positive cap");
    storage()
        .put(&key, vec![0u8; cap + 1], "image/png")
        .await
        .expect("the oversize object lands");
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, 'cutout', $3, 'image/png')",
    )
    .bind(media)
    .bind(account)
    .bind(&key)
    .execute(&pool)
    .await?;

    let response = send(
        router(pool.clone(), false),
        get_with_auth(&format!("/v1/media/{media}"), &format!("Bearer {token}")),
    )
    .await;

    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
    let left: i64 = sqlx::query_scalar("select count(*) from media_object where id = $1")
        .bind(media)
        .fetch_one(&pool)
        .await?;
    assert_eq!(left, 0, "the row goes with the object it described");
    assert!(
        storage().head(&key).await.expect("head").is_none(),
        "and the bytes are gone from the store, not merely unreferenced"
    );
    let _ = json!({});
    Ok(())
}

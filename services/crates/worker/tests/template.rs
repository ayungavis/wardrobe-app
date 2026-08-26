use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_storage::{Settings, Storage};
use wardrobe_worker::illustration::Provider;
use wardrobe_worker::{Outcome, run_one, template};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

const GARMENT_NAME: &str = "Ayung's favourite blue shirt";

fn flat_png(width: u32, height: u32) -> Vec<u8> {
    let canvas = image::RgbImage::from_pixel(width, height, image::Rgb([70, 110, 150]));
    let mut bytes = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgb8(canvas)
        .write_to(&mut bytes, image::ImageFormat::Png)
        .expect("a png");
    bytes.into_inner()
}

fn store() -> Storage {
    fn env(name: &str, fallback: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| fallback.to_owned())
    }
    Storage::new(&Settings {
        endpoint: env("TEST_S3_ENDPOINT", "http://localhost:9100"),
        region: env("TEST_S3_REGION", "us-east-1"),
        bucket: env("TEST_S3_BUCKET", "wardrobe"),
        access_key_id: env("TEST_S3_ACCESS_KEY_ID", "wardrobe"),
        secret_access_key: env("TEST_S3_SECRET_ACCESS_KEY", "wardrobe-dev-secret"),
        path_style: true,
        presign_ttl: std::time::Duration::from_secs(300),
    })
}

fn provider(server: &MockServer) -> Provider {
    Provider {
        client: reqwest::Client::new(),
        base_url: server.uri(),
        api_key: "test-key".to_owned(),
    }
}

async fn answer(server: &MockServer, template: ResponseTemplate) {
    Mock::given(method("POST"))
        .and(path("/images"))
        .respond_with(template)
        .mount(server)
        .await;
}

async fn sent_body(server: &MockServer) -> Value {
    let requests = server.received_requests().await.expect("recording");
    serde_json::from_slice(&requests.first().expect("one request").body).expect("json body")
}

async fn put_media(pool: &PgPool, account: Uuid, kind: &str) -> sqlx::Result<Uuid> {
    let media = Uuid::now_v7();
    let key = format!("{account}/{kind}/{media}");
    store()
        .put(&key, flat_png(320, 320), "image/png")
        .await
        .expect("the object lands");
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, $3, $4, 'image/png')",
    )
    .bind(media)
    .bind(account)
    .bind(kind)
    .bind(&key)
    .execute(pool)
    .await?;
    Ok(media)
}

struct Scene {
    account: Uuid,
    request: Uuid,
}

async fn scene(pool: &PgPool, garments: usize) -> sqlx::Result<Scene> {
    let account = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(account)
        .execute(pool)
        .await?;
    sqlx::query(
        "insert into ai_provider_allowlist
             (provider_slug, forbids_training, retention_policy, approved_by)
         values ('a-provider', true, 'zero', 'the test')",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "update ai_model_config
            set active_model = 'primary/model', alternate_model = null, prompt_version = 'p1'
          where capability = 'outfit_template'",
    )
    .execute(pool)
    .await?;

    let person = put_media(pool, account, "original").await?;
    let mut wardrobe = Vec::with_capacity(garments);
    for index in 0..garments {
        let media = put_media(pool, account, "cutout").await?;
        wardrobe.push(serde_json::json!({
            "mediaId": media,
            "name": format!("{GARMENT_NAME} {index}"),
            "wears": 3,
        }));
    }

    let request = Uuid::now_v7();
    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload, max_attempts, run_after)
         values ($1, $2, $3, $4, $5, 2, now() - interval '1 minute')",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(wardrobe_db::OUTFIT_TEMPLATE)
    .bind(format!("{request}:blisterGreen"))
    .bind(json!({
        "requestId": request.to_string(),
        "template": "blisterGreen",
        "personMediaId": person.to_string(),
        "garments": wardrobe,
    }))
    .execute(pool)
    .await?;

    Ok(Scene { account, request })
}

async fn run(pool: &PgPool, server: &MockServer) -> Outcome {
    let provider = provider(server);
    let storage = store();
    run_one(pool, wardrobe_db::OUTFIT_TEMPLATE, |job| async move {
        template::render_for(pool, &storage, &provider, &job, true).await
    })
    .await
    .expect("the claim itself works")
    .expect("a job was waiting")
}

fn rendered() -> Value {
    json!({
        "provider": "a-provider",
        "usage": { "prompt_tokens": 11, "completion_tokens": 22 },
        "data": [{ "b64_json": STANDARD.encode(flat_png(1024, 1365)),
                   "media_type": "image/png" }]
    })
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_worker_sends_the_photo_and_every_garment_as_references(
    pool: PgPool,
) -> sqlx::Result<()> {
    let scene = scene(&pool, 3).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered()),
    )
    .await;

    run(&pool, &server).await;

    let sent = sent_body(&server).await;
    let references = sent["input_references"]
        .as_array()
        .expect("an array of references");
    assert_eq!(
        references.len(),
        4,
        "one person plus three garments; a single-image request drops the outfit"
    );
    let stored: i64 =
        sqlx::query_scalar("select count(*) from outfit_template where request_id = $1")
            .bind(scene.request)
            .fetch_one(&pool)
            .await?;
    assert_eq!(stored, 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_refused_generation_leaves_no_half_written_row(pool: PgPool) -> sqlx::Result<()> {
    let scene = scene(&pool, 2).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(422)).await;

    run(&pool, &server).await;

    let stored: i64 =
        sqlx::query_scalar("select count(*) from outfit_template where request_id = $1")
            .bind(scene.request)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        stored, 0,
        "a row with no image behind it renders as a blank canvas"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_ledger_records_the_attempt_without_the_garment_names(
    pool: PgPool,
) -> sqlx::Result<()> {
    let scene = scene(&pool, 2).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered()),
    )
    .await;

    run(&pool, &server).await;

    let ledger: Vec<(String, String)> =
        sqlx::query_as("select capability, model from ai_inference_attempt where account_id = $1")
            .bind(scene.account)
            .fetch_all(&pool)
            .await?;
    assert_eq!(ledger.len(), 1);
    assert_eq!(ledger[0].0, "outfit_template");

    let leaked: i64 = sqlx::query_scalar(
        "select count(*) from ai_inference_attempt
          where account_id = $1 and model like '%' || $2 || '%'",
    )
    .bind(scene.account)
    .bind(GARMENT_NAME)
    .fetch_one(&pool)
    .await?;
    assert_eq!(leaked, 0, "PRD 18.12 keeps user text out of the ledger");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_request_asks_for_the_canvas_shape(pool: PgPool) -> sqlx::Result<()> {
    scene(&pool, 2).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered()),
    )
    .await;

    run(&pool, &server).await;

    let sent = sent_body(&server).await;
    assert_eq!(
        sent["aspect_ratio"], "9:16",
        "the page is drawn scaledToFill on a 9:16 canvas, so a wider one loses its sides"
    );
    Ok(())
}

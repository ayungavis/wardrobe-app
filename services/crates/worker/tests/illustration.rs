use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_storage::{Settings, Storage};
use wardrobe_worker::illustration::{self, Provider};
use wardrobe_worker::{Outcome, run_one};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

// ------------------------------------------------------------------- fixtures

const ITEM_NAME: &str = "Ayung's favourite blue shirt";

fn flat_png(width: u32, height: u32) -> Vec<u8> {
    let canvas = image::RgbImage::from_pixel(width, height, image::Rgb([70, 110, 150]));
    let mut bytes = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgb8(canvas)
        .write_to(&mut bytes, image::ImageFormat::Png)
        .expect("a png");
    bytes.into_inner()
}

fn cutout_bytes() -> Vec<u8> {
    flat_png(512, 512)
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

fn rendered_image() -> Value {
    rendered_canvas(1024, 1024)
}

fn rendered_canvas(width: u32, height: u32) -> Value {
    json!({
        "provider": "a-provider",
        "usage": { "prompt_tokens": 11, "completion_tokens": 22 },
        "data": [{ "b64_json": STANDARD.encode(flat_png(width, height)),
                   "media_type": "image/png" }]
    })
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

struct Scene {
    item: Uuid,
    job: Uuid,
}

async fn configure(pool: &PgPool, alternate: Option<&str>) -> sqlx::Result<()> {
    sqlx::query(
        "insert into ai_provider_allowlist (provider_slug, forbids_training, retention_policy, approved_by)
         values ('a-provider', true, 'zero', 'the test')",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "insert into ai_model_config
             (capability, model_class, active_model, alternate_model, prompt_version, updated_by)
         values ('illustration', 'image', 'primary/model', $1, 'p1', 'the test')",
    )
    .bind(alternate)
    .execute(pool)
    .await?;
    Ok(())
}

async fn scene(pool: &PgPool, with_cutout: bool) -> sqlx::Result<Scene> {
    scene_carrying(pool, with_cutout.then(cutout_bytes)).await
}

async fn scene_carrying(pool: &PgPool, cutout: Option<Vec<u8>>) -> sqlx::Result<Scene> {
    let account = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(account)
        .execute(pool)
        .await?;

    let item = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, name, change_seq, illustration_state)
         values ($1, $2, 'top', $3, 1, 'queued')",
    )
    .bind(item)
    .bind(account)
    .bind(ITEM_NAME)
    .execute(pool)
    .await?;

    if let Some(cutout) = cutout {
        let media = Uuid::now_v7();
        let key = format!("{account}/cutout/{media}");
        store()
            .put(&key, cutout, "image/png")
            .await
            .expect("the cut-out lands");
        sqlx::query(
            "insert into media_object (id, account_id, kind, storage_key, content_type)
             values ($1, $2, 'cutout', $3, 'image/png')",
        )
        .bind(media)
        .bind(account)
        .bind(&key)
        .execute(pool)
        .await?;
        sqlx::query(
            "insert into item_cutout (id, account_id, item_id, media_object_id, change_seq)
             values ($1, $2, $3, $4, 2)",
        )
        .bind(Uuid::now_v7())
        .bind(account)
        .bind(item)
        .bind(media)
        .execute(pool)
        .await?;
    }

    let job = Uuid::now_v7();
    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload, max_attempts, run_after)
         values ($1, $2, $3, $4, jsonb_build_object('itemId', $4), 2, now() - interval '1 minute')",
    )
    .bind(job)
    .bind(account)
    .bind(wardrobe_db::ILLUSTRATION)
    .bind(item.to_string())
    .execute(pool)
    .await?;

    Ok(Scene { item, job })
}

async fn run(pool: &PgPool, server: &MockServer, final_attempt: bool) -> Outcome {
    let provider = provider(server);
    let storage = store();
    let claimed = run_one(pool, wardrobe_db::ILLUSTRATION, |job| async move {
        illustration::render_for(pool, &storage, &provider, &job, final_attempt).await
    })
    .await
    .expect("the claim itself works");

    match claimed {
        Some(outcome) => outcome,
        None => panic!("a job was waiting; {}", queue_state(pool).await),
    }
}

async fn state_of(pool: &PgPool, item: Uuid) -> (String, Option<Uuid>) {
    sqlx::query_as(
        "select illustration_state, current_illustration_id from wardrobe_item where id = $1",
    )
    .bind(item)
    .fetch_one(pool)
    .await
    .expect("the item row")
}

async fn attempts(pool: &PgPool, job: Uuid) -> Vec<(i32, String, String)> {
    sqlx::query_as(
        "select attempt_no, model, status from ai_inference_attempt
          where job_id = $1 order by attempt_no",
    )
    .bind(job)
    .fetch_all(pool)
    .await
    .expect("attempt rows")
}

// -------------------------------------------------------------- happy path

#[sqlx::test(migrations = "../../migrations")]
async fn a_valid_render_is_handed_to_styling_rather_than_shown(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Succeeded);

    let (state, current) = state_of(&pool, scene.item).await;
    assert_eq!(
        (state.as_str(), current),
        ("rendering", None),
        "a generation without its sticker treatment is not a finished illustration"
    );
    let versions: i64 =
        sqlx::query_scalar("select count(*) from item_illustration where item_id = $1")
            .bind(scene.item)
            .fetch_one(&pool)
            .await?;
    assert_eq!(versions, 0);

    let queued: i64 = sqlx::query_scalar("select count(*) from job where kind = $1")
        .bind(wardrobe_db::STYLISE_ILLUSTRATION)
        .fetch_one(&pool)
        .await?;
    assert_eq!(queued, 1, "the generated image waits for post-processing");

    let stored: i64 =
        sqlx::query_scalar("select count(*) from media_object where kind = 'illustration'")
            .fetch_one(&pool)
            .await?;
    assert_eq!(stored, 1, "the render is paid for once, so it is kept");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_request_carries_every_parameter_the_specification_names(
    pool: PgPool,
) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    run(&pool, &server, false).await;

    let body = sent_body(&server).await;
    assert_eq!(body["resolution"], "1K");
    assert_eq!(body["aspect_ratio"], "1:1");
    assert_eq!(body["n"], 1);
    assert!(body["seed"].is_i64());
    assert_eq!(
        body["provider"]["zdr"], true,
        "zero data retention is the routing policy, not a preference"
    );
    assert_eq!(body["input_references"].as_array().expect("array").len(), 1);
    assert!(
        body["input_references"][0]["image_url"]["url"]
            .as_str()
            .expect("a data url")
            .starts_with("data:image/"),
        "the provider must never receive an object url"
    );
    for unsupported in ["background", "output_format", "quality", "negative_prompt"] {
        assert!(
            body.get(unsupported).is_none(),
            "{unsupported} is not advertised by this model, so sending it is a guess"
        );
    }
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_transient_failure_retries_the_same_pinned_seed(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, Some("alternate/model")).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(503)).await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Retrying);
    sqlx::query("update job set status = 'pending', run_after = now() where id = $1")
        .bind(scene.job)
        .execute(&pool)
        .await?;
    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    let pinned: Vec<(String, Option<i64>)> = sqlx::query_as(
        "select model, seed from ai_inference_attempt where job_id = $1 order by attempt_no",
    )
    .bind(scene.job)
    .fetch_all(&pool)
    .await?;
    assert_eq!(pinned.len(), 2);
    assert_eq!(
        pinned[0], pinned[1],
        "a timeout is not a reason to change the request; the attempt stays pinned"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_attempt_row_carries_no_user_content(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Succeeded);

    let row: Value =
        sqlx::query_scalar("select to_jsonb(a) from ai_inference_attempt a where job_id = $1")
            .bind(scene.job)
            .fetch_one(&pool)
            .await?;
    let printed = row.to_string();

    for forbidden in [ITEM_NAME, "cut-out", "styled garment", "Redraw"] {
        assert!(
            !printed.contains(forbidden),
            "an accounting row that quotes {forbidden} is a log carrying user content: {printed}"
        );
    }
    assert_eq!(row["status"], "succeeded");
    assert_eq!(row["provider_route"], "a-provider");
    Ok(())
}

// ---------------------------------------------------------------- pinning

#[sqlx::test(migrations = "../../migrations")]
async fn a_refusal_moves_to_the_alternate_as_its_own_pinned_attempt(
    pool: PgPool,
) -> sqlx::Result<()> {
    configure(&pool, Some("alternate/model")).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(400)).await;

    assert_eq!(
        run(&pool, &server, false).await,
        Outcome::Retrying,
        "a refusal with an alternate configured is not the end of the chain"
    );
    sqlx::query("update job set status = 'pending', run_after = now() where id = $1")
        .bind(scene.job)
        .execute(&pool)
        .await?;
    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    let rows = attempts(&pool, scene.job).await;
    assert_eq!(rows.len(), 2, "each pinned model gets its own row");
    assert_eq!(rows[0].1, "primary/model");
    assert_eq!(
        rows[1].1, "alternate/model",
        "moving to the alternate is a distinct pinned attempt, never a silent swap"
    );
    assert_eq!(state_of(&pool, scene.item).await.0, "failed");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_rate_limited_provider_moves_to_the_alternate(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, Some("alternate/model")).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(429)).await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Retrying);
    sqlx::query("update job set status = 'pending', run_after = now() where id = $1")
        .bind(scene.job)
        .execute(&pool)
        .await?;
    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    let rows = attempts(&pool, scene.job).await;
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].1, "primary/model");
    assert_eq!(
        rows[1].1, "alternate/model",
        "a provider out of quota answers 429 forever; retrying the same model until the \
         attempts run out never reaches the alternate the fallback chain exists for (FR-075)"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_refusal_records_the_http_status(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(404)).await;

    run(&pool, &server, true).await;

    let status: Option<i32> =
        sqlx::query_scalar("select http_status from ai_inference_attempt where job_id = $1")
            .bind(scene.job)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        status,
        Some(404),
        "401, 402, and 404 must be tellable apart from the ledger alone"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_prompt_names_the_garment_it_is_drawing(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    sqlx::query("update wardrobe_item set category = 'bottom', name = 'Blue shorts' where id = $1")
        .bind(scene.item)
        .execute(&pool)
        .await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    run(&pool, &server, false).await;

    let prompt = sent_body(&server).await["prompt"]
        .as_str()
        .expect("a prompt")
        .to_lowercase();
    assert!(
        prompt.contains("bottom"),
        "a model shown only a cut-out draws a shirt for a pair of shorts"
    );
    assert!(
        prompt.contains("blue shorts"),
        "the item's own name is the sharpest hint there is"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_regeneration_note_reaches_the_prompt(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    sqlx::query("update job set payload = payload || jsonb_build_object('note', $2) where id = $1")
        .bind(scene.job)
        .bind("these are shorts, not a shirt")
        .execute(&pool)
        .await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    run(&pool, &server, false).await;

    let prompt = sent_body(&server).await["prompt"]
        .as_str()
        .expect("a prompt")
        .to_owned();
    assert!(
        prompt.contains("these are shorts, not a shirt"),
        "the whole point of asking again is being able to say what went wrong"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_prompt_asks_for_the_margin_the_sticker_stage_needs(
    pool: PgPool,
) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    run(&pool, &server, false).await;

    let prompt = sent_body(&server).await["prompt"]
        .as_str()
        .expect("a prompt")
        .to_owned();
    assert!(
        prompt.contains(illustration::sticker::FRAMING_RULE),
        "a render that fills the frame is refused later, so the request has to ask for the margin"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_operators_own_prompt_still_carries_the_framing_rule(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    scene(&pool, true).await?;
    sqlx::query("update ai_model_config set params = '{\"prompt\": \"Draw it however.\"}'::jsonb")
        .execute(&pool)
        .await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    run(&pool, &server, false).await;

    let prompt = sent_body(&server).await["prompt"]
        .as_str()
        .expect("a prompt")
        .to_owned();
    assert!(
        prompt.starts_with("Draw it however."),
        "the operator's words still lead"
    );
    assert!(
        prompt.contains(illustration::sticker::FRAMING_RULE),
        "the sticker stage's requirement is not a preference an override may drop"
    );
    Ok(())
}

// ----------------------------------------------------------------- limits

#[sqlx::test(migrations = "../../migrations")]
async fn a_limit_hit_records_it_and_calls_nobody(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    sqlx::query(
        "insert into ai_usage_limit (id, scope, capability, window_seconds, max_requests, updated_by)
         values ($1, 'global', 'illustration', 3600, 1, 'the test')",
    )
    .bind(Uuid::now_v7())
    .execute(&pool)
    .await?;
    sqlx::query(
        "insert into ai_inference_attempt
             (id, capability, attempt_no, model, prompt_version, status)
         values ($1, 'illustration', 1, 'primary/model', 'p1', 'succeeded')",
    )
    .bind(Uuid::now_v7())
    .execute(&pool)
    .await?;

    let server = MockServer::start().await;
    assert_eq!(run(&pool, &server, false).await, Outcome::Succeeded);

    assert_eq!(attempts(&pool, scene.job).await[0].2, "skipped_limit");
    assert_eq!(state_of(&pool, scene.item).await.0, "failed");
    assert!(
        server
            .received_requests()
            .await
            .expect("recording")
            .is_empty(),
        "a limit that still spends money is not a limit"
    );
    Ok(())
}

// --------------------------------------------------------------- fallbacks

#[sqlx::test(migrations = "../../migrations")]
async fn a_refusal_leaves_the_item_usable_from_its_cutout(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(400)).await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Succeeded);

    assert_eq!(attempts(&pool, scene.job).await[0].2, "refused");
    let (state, current) = state_of(&pool, scene.item).await;
    assert_eq!(state, "failed");
    assert_eq!(current, None);

    let versions: i64 =
        sqlx::query_scalar("select count(*) from item_illustration where item_id = $1")
            .bind(scene.item)
            .fetch_one(&pool)
            .await?;
    assert_eq!(versions, 0, "nothing refused ever becomes a stored version");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_malformed_reply_is_invalid_output_not_a_version(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200)
            .set_body_json(json!({ "data": [{ "b64_json": "bm90IGFuIGltYWdl" }] })),
    )
    .await;

    assert_eq!(
        run(&pool, &server, false).await,
        Outcome::Retrying,
        "a malformed reply is worth asking again within the quality budget"
    );
    sqlx::query("update job set status = 'pending', run_after = now() where id = $1")
        .bind(scene.job)
        .execute(&pool)
        .await?;
    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    let rows = attempts(&pool, scene.job).await;
    assert!(rows.iter().all(|(_, _, status)| status == "invalid_output"));
    assert_eq!(state_of(&pool, scene.item).await.0, "failed");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_item_without_a_cutout_never_reaches_the_provider(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, false).await?;
    let server = MockServer::start().await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Succeeded);

    assert_eq!(state_of(&pool, scene.item).await.0, "failed");
    assert!(
        server
            .received_requests()
            .await
            .expect("recording")
            .is_empty(),
        "the cut-out is the only thing section 18.16 ever permits to be sent"
    );
    assert!(attempts(&pool, scene.job).await.is_empty());
    Ok(())
}

// ------------------------------------------------------- readiness gating

#[sqlx::test(migrations = "../../migrations")]
async fn the_capability_is_not_ready_until_a_provider_is_allowlisted(
    pool: PgPool,
) -> sqlx::Result<()> {
    assert!(!wardrobe_worker::inference::ready(&pool, illustration::CAPABILITY).await?);

    sqlx::query(
        "insert into ai_model_config
             (capability, model_class, active_model, prompt_version, updated_by)
         values ('illustration', 'image', 'primary/model', 'p1', 'the test')",
    )
    .execute(&pool)
    .await?;
    assert!(
        !wardrobe_worker::inference::ready(&pool, illustration::CAPABILITY).await?,
        "an empty allowlist means off, never open"
    );

    sqlx::query(
        "insert into ai_provider_allowlist (provider_slug, forbids_training, retention_policy, approved_by)
         values ('a-provider', true, 'zero', 'the test')",
    )
    .execute(&pool)
    .await?;
    assert!(wardrobe_worker::inference::ready(&pool, illustration::CAPABILITY).await?);
    Ok(())
}

// --------------------------------------------------- what may be sent

fn png_claiming(width: u32, height: u32) -> Vec<u8> {
    let mut bytes = flat_png(8, 8);
    bytes[16..20].copy_from_slice(&width.to_be_bytes());
    bytes[20..24].copy_from_slice(&height.to_be_bytes());
    let crc = crc32(&bytes[12..29]);
    bytes[29..33].copy_from_slice(&crc.to_be_bytes());
    bytes
}

fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = 0xffff_ffff_u32;
    for byte in bytes {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                (crc >> 1) ^ 0xedb8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

fn jpeg_carrying_exif() -> Vec<u8> {
    let canvas = image::RgbImage::from_pixel(64, 64, image::Rgb([70, 110, 150]));
    let mut body = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgb8(canvas)
        .write_to(&mut body, image::ImageFormat::Jpeg)
        .expect("a jpeg");
    let body = body.into_inner();

    let payload = b"Exif\0\0MM\0\x2aWARDROBE-SECRET-CAMERA-TAG";
    let length = u16::try_from(payload.len() + 2).expect("a short segment");
    let mut spliced = vec![0xff, 0xd8, 0xff, 0xe1];
    spliced.extend_from_slice(&length.to_be_bytes());
    spliced.extend_from_slice(payload);
    spliced.extend_from_slice(&body[2..]);
    spliced
}

async fn reached_provider(server: &MockServer) -> usize {
    server.received_requests().await.expect("recording").len()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_cutout_over_the_pixel_budget_never_reaches_the_provider(
    pool: PgPool,
) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    sqlx::query("update ai_model_config set params = '{\"maxInputPixels\": 1024}'::jsonb")
        .execute(&pool)
        .await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    assert_eq!(
        reached_provider(&server).await,
        0,
        "a cut-out we refuse must never be sent to a third party, nor billed for"
    );
    assert!(
        attempts(&pool, scene.job).await.is_empty(),
        "no inference happened, so no attempt row may claim one did"
    );
    assert_eq!(state_of(&pool, scene.item).await.0, "failed");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_header_claiming_a_huge_canvas_is_refused_before_decoding(
    pool: PgPool,
) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let bomb = png_claiming(60_000, 60_000);
    assert!(
        bomb.len() < 1_000,
        "the bomb is small on disk; that is the point"
    );
    scene_carrying(&pool, Some(bomb)).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    assert_eq!(reached_provider(&server).await, 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_cutout_that_is_not_square_is_refused(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    scene_carrying(&pool, Some(flat_png(640, 480))).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    assert_eq!(reached_provider(&server).await, 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn bytes_that_are_not_an_image_are_refused(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    scene_carrying(&pool, Some(b"the confirmed normalised cut-out".to_vec())).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    assert_eq!(reached_provider(&server).await, 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn camera_metadata_never_travels_with_the_cutout(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let original = jpeg_carrying_exif();
    assert!(
        original
            .windows(23)
            .any(|window| window == b"WARDROBE-SECRET-CAMERA-TAG"[..23].as_ref()),
        "the fixture has to carry the tag before the test can prove it is gone"
    );
    scene_carrying(&pool, Some(original)).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_image()),
    )
    .await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Succeeded);

    let sent = sent_body(&server).await;
    let reference = sent["input_references"][0]["image_url"]["url"]
        .as_str()
        .expect("a data uri");
    let (prefix, encoded) = reference.split_once(',').expect("a data uri");
    assert_eq!(prefix, "data:image/png;base64");
    let forwarded = STANDARD.decode(encoded).expect("base64");
    assert!(
        !forwarded
            .windows(23)
            .any(|window| window == b"WARDROBE-SECRET-CAMERA-TAG"[..23].as_ref()),
        "re-encoding is what strips metadata, and this is what proves it did"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_generation_on_the_wrong_canvas_is_invalid_output(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool, true).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(rendered_canvas(640, 480)),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    assert_eq!(attempts(&pool, scene.job).await[0].2, "invalid_output");
    let (state, current) = state_of(&pool, scene.item).await;
    assert_eq!(state, "failed");
    assert_eq!(
        current, None,
        "a wrong canvas never becomes a stored version"
    );
    Ok(())
}

// ------------------------------------------------------- the clock

#[tokio::test]
async fn a_provider_that_never_answers_gives_up_instead_of_hanging() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/images"))
        .respond_with(ResponseTemplate::new(200).set_delay(std::time::Duration::from_secs(30)))
        .mount(&server)
        .await;

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_millis(100))
        .build()
        .expect("a client");

    let outcome = illustration::openrouter::render(
        &client,
        &server.uri(),
        "test-key",
        &live_ask("a/model", b"cut-out"),
    )
    .await;

    assert_eq!(
        outcome.err().map(|rejection| rejection.failure),
        Some(illustration::openrouter::Failure::Unavailable),
        "a hung provider must be retryable, not a worker that stops claiming anything"
    );
    assert!(
        illustration::openrouter::Failure::Unavailable.status() == "failed",
        "and it settles as failed only after the attempts run out"
    );
}

// --------------------------------------------------- the shape, for real

const FLAT_SQUARE_PNG: &str = "iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAIAAADTED8xAAACAElEQVR42u3TQQ0AAAjEsFOHHOSglz\
                               caaFIFS5bqgbciAQYAA4ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAYA\
                               A4ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAYAA4ABMIAKGAAMAAYAA4\
                               ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAYA\
                               A4ABwABgADAAGAAMAAYAA4ABwABgADAAGAAMAAbAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgADgA\
                               HAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgAD\
                               gAHAAGAAMAAGUAEDgAHAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgADgA\
                               HAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgADgAHAAGAAMAAYAAwABgADgAHAABgADAAGAAOAAcAA\
                               YAAwABgADAAGAAOAAcAAYAAwABgADAAGAAOAAcAAYAAwABgADAAGAAOAAcAAYAAwABgADAAGAAOAAc\
                               AAYAAwABgADAAGAAOAAcAAYAAwAFwLWzETVzKC750AAAAASUVORK5CYII=";

fn live_credentials() -> (String, String) {
    (
        std::env::var("OPENROUTER_API_KEY").expect("OPENROUTER_API_KEY"),
        std::env::var("OPENROUTER_TEST_MODEL").expect("OPENROUTER_TEST_MODEL"),
    )
}

fn live_base_url() -> String {
    std::env::var("OPENROUTER_BASE_URL")
        .unwrap_or_else(|_| illustration::openrouter::DEFAULT_BASE_URL.to_owned())
}

#[tokio::test]
#[ignore = "needs OPENROUTER_API_KEY and OPENROUTER_TEST_MODEL; optional OPENROUTER_TEST_CUTOUT (png path)"]
async fn a_real_cutout_renders_end_to_end() {
    let api_key = std::env::var("OPENROUTER_API_KEY").expect("OPENROUTER_API_KEY");
    let model = std::env::var("OPENROUTER_TEST_MODEL").expect("OPENROUTER_TEST_MODEL");
    let cutout = match std::env::var("OPENROUTER_TEST_CUTOUT") {
        Ok(path) => std::fs::read(&path).expect("the cutout file"),
        Err(_) => cutout_bytes(),
    };

    let seed = std::env::var("OPENROUTER_TEST_SEED")
        .ok()
        .and_then(|raw| raw.parse().ok())
        .unwrap_or(184_726);
    let prompt = std::env::var("OPENROUTER_TEST_PROMPT").ok();
    let mut ask = live_ask(&model, &cutout);
    ask.seed = seed;
    if let Some(prompt) = prompt.as_deref() {
        ask.prompt = prompt;
    }
    let payload = illustration::openrouter::payload(&ask);
    let body = serde_json::to_vec(&payload).expect("a payload");
    println!(
        "payload bytes: {} (cutout bytes: {})",
        body.len(),
        cutout.len()
    );

    let client = reqwest::Client::new();
    let response = client
        .post(format!(
            "{}/images",
            illustration::openrouter::DEFAULT_BASE_URL
        ))
        .bearer_auth(&api_key)
        .json(&payload)
        .send()
        .await
        .expect("a response");
    let status = response.status();
    let text = response.text().await.unwrap_or_default();

    if status.is_success() {
        let parsed: Value = serde_json::from_str(&text).expect("a json body");
        let encoded = parsed["data"][0]["b64_json"].as_str().expect("an image");
        let image = STANDARD.decode(encoded).expect("decodable image bytes");
        let out = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("live-sticker.png");
        std::fs::write(&out, &image).expect("writable target dir");
        println!("sticker written: {} ({} bytes)", out.display(), image.len());
    } else {
        let shown: String = text.chars().take(4000).collect();
        println!("provider said {status}:\n{shown}");
    }
    assert!(
        status.is_success(),
        "the provider refused; its verbatim answer is printed above"
    );
}

static LIVE_PROMPT: std::sync::LazyLock<String> = std::sync::LazyLock::new(|| {
    format!(
        "Redraw this as a flat-lay product illustration. Garment only, no person. {}",
        illustration::sticker::FRAMING_RULE
    )
});

fn live_ask<'a>(model: &'a str, cutout: &'a [u8]) -> illustration::openrouter::Ask<'a> {
    illustration::openrouter::Ask {
        model,
        prompt: LIVE_PROMPT.as_str(),
        cutout,
        content_type: "image/png",
        resolution: illustration::openrouter::DEFAULT_RESOLUTION,
        aspect_ratio: illustration::openrouter::DEFAULT_ASPECT_RATIO,
        seed: 184_726,
    }
}

#[tokio::test]
#[ignore = "needs OPENROUTER_API_KEY and OPENROUTER_TEST_MODEL in services/.env"]
async fn the_live_model_advertises_every_parameter_this_client_sends() {
    let (api_key, model) = live_credentials();

    let advertised: Value = reqwest::Client::new()
        .get(format!("{}/images/models", live_base_url()))
        .bearer_auth(&api_key)
        .send()
        .await
        .expect("the capability descriptor is reachable")
        .json()
        .await
        .expect("json");

    let listed = advertised["data"]
        .as_array()
        .expect("a data array")
        .iter()
        .find(|entry| entry["id"] == model.as_str())
        .unwrap_or_else(|| panic!("{model} is not offered by this endpoint"));
    let supported = &listed["supported_parameters"];

    let cutout = STANDARD
        .decode(FLAT_SQUARE_PNG.replace(char::is_whitespace, ""))
        .expect("a png");
    let sent = illustration::openrouter::payload(&live_ask(&model, &cutout));
    let sent = sent.as_object().expect("an object");

    for parameter in sent.keys() {
        if ["model", "prompt", "provider"].contains(&parameter.as_str()) {
            continue;
        }
        assert!(
            !supported[parameter].is_null(),
            "we send {parameter} but {model} does not advertise it: {supported}"
        );
    }
    assert_eq!(supported["resolution"]["values"][0], "1K");
    assert_eq!(supported["n"]["max"], 1);
}

#[tokio::test]
#[ignore = "needs OPENROUTER_API_KEY, OPENROUTER_TEST_MODEL, and credits on the account"]
async fn the_live_provider_answers_in_the_shape_this_client_parses() {
    let (api_key, model) = live_credentials();
    let base_url = live_base_url();
    let cutout = STANDARD
        .decode(FLAT_SQUARE_PNG.replace(char::is_whitespace, ""))
        .expect("a png");

    let raw = reqwest::Client::new()
        .post(format!("{base_url}/images"))
        .bearer_auth(&api_key)
        .json(&illustration::openrouter::payload(&live_ask(
            &model, &cutout,
        )))
        .send()
        .await
        .expect("the images endpoint is reachable");

    let status = raw.status().as_u16();
    let body: Value = raw.json().await.expect("a json body");
    assert_ne!(
        status, 402,
        "the account has no credits, so this run says nothing about the shape: {}",
        body["error"]["message"]
    );
    assert!(
        (200..300).contains(&status),
        "status {status}, and the shape stays unverified: {body}"
    );

    assert!(
        body["data"][0]["b64_json"].is_string(),
        "the client reads data[].b64_json; the live reply carries {body}"
    );

    let rendered = illustration::openrouter::render(
        &reqwest::Client::new(),
        &base_url,
        &api_key,
        &live_ask(&model, &cutout),
    )
    .await
    .expect("the live provider answers in the shape this client parses");

    assert!(!rendered.image.is_empty());
    assert!(rendered.content_type.starts_with("image/"));

    eprintln!(
        "live accounting — route: {:?}, prompt tokens: {:?}, completion tokens: {:?}",
        rendered.provider_route, rendered.input_tokens, rendered.output_tokens
    );

    let canvas = image::load_from_memory(&rendered.image)
        .expect("the generation decodes")
        .to_rgba8();
    let mask =
        illustration::sticker::separate(&canvas, illustration::sticker::Style::default().tolerance);
    let report = mask.report();
    let verdict =
        illustration::sticker::inspect(&mask, illustration::sticker::MaskBounds::default());

    eprintln!(
        "live mask — corner spread: {}, coverage: {}permille, components: {}, dominant: {}permille, \
         touches edge: {}, verdict: {verdict:?}",
        corner_spread(&canvas),
        report.coverage_permille,
        report.components,
        report.dominant_share_permille,
        report.touches_edge
    );
}

fn corner_spread(canvas: &image::RgbaImage) -> u32 {
    let (width, height) = canvas.dimensions();
    let corners = [
        canvas.get_pixel(0, 0),
        canvas.get_pixel(width - 1, 0),
        canvas.get_pixel(0, height - 1),
        canvas.get_pixel(width - 1, height - 1),
    ];
    (0..3)
        .map(|channel| {
            let values: Vec<u32> = corners
                .iter()
                .map(|pixel| u32::from(pixel[channel]))
                .collect();
            values.iter().max().copied().unwrap_or(0) - values.iter().min().copied().unwrap_or(0)
        })
        .max()
        .unwrap_or(0)
}

async fn queue_state(pool: &PgPool) -> String {
    let database: String = sqlx::query_scalar("select current_database()")
        .fetch_one(pool)
        .await
        .unwrap_or_else(|error| format!("<{error}>"));
    let rows: Vec<(Uuid, String, String, i32, bool)> = sqlx::query_as(
        "select id, kind, status, attempts, run_after <= now() from job order by run_after",
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    format!("database {database}, {} job row(s): {rows:?}", rows.len())
}

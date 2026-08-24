use image::{Rgba, RgbaImage};
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_storage::{Settings, Storage};
use wardrobe_worker::illustration;
use wardrobe_worker::{Outcome, run_one};

// ------------------------------------------------------------------- fixtures

fn store() -> Storage {
    fn env(name: &str, fallback: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| fallback.to_owned())
    }
    Storage::new(&Settings {
        endpoint: env("S3_ENDPOINT", "http://localhost:9100"),
        region: env("S3_REGION", "us-east-1"),
        bucket: env("S3_BUCKET", "wardrobe"),
        access_key_id: env("S3_ACCESS_KEY_ID", "wardrobe"),
        secret_access_key: env("S3_SECRET_ACCESS_KEY", "wardrobe-dev-secret"),
        path_style: true,
        presign_ttl: std::time::Duration::from_secs(300),
    })
}

fn generation(side: u32, shapes: &[(u32, u32, u32, u32)]) -> Vec<u8> {
    let mut canvas = RgbaImage::from_pixel(side, side, Rgba([240, 240, 238, 255]));
    for (left, top, width, height) in shapes {
        for y in *top..top + height {
            for x in *left..left + width {
                canvas.put_pixel(x, y, Rgba([40, 90, 160, 255]));
            }
        }
    }
    let mut png = std::io::Cursor::new(Vec::new());
    image::DynamicImage::ImageRgba8(canvas)
        .write_to(&mut png, image::ImageFormat::Png)
        .expect("a png");
    png.into_inner()
}

fn a_garment() -> Vec<u8> {
    generation(256, &[(64, 64, 128, 128)])
}

struct Scene {
    account: Uuid,
    item: Uuid,
    media: Uuid,
}

async fn scene(pool: &PgPool, bytes: Vec<u8>) -> sqlx::Result<Scene> {
    let account = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(account)
        .execute(pool)
        .await?;

    let item = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq, illustration_state)
         values ($1, $2, 'top', 1, 'rendering')",
    )
    .bind(item)
    .bind(account)
    .execute(pool)
    .await?;

    let media = Uuid::now_v7();
    let key = format!("{account}/illustration/{media}");
    store()
        .put(&key, bytes, "image/png")
        .await
        .expect("the generation lands");
    sqlx::query(
        "insert into media_object
             (id, account_id, kind, storage_key, content_type, uploaded_at)
         values ($1, $2, 'illustration', $3, 'image/png', now())",
    )
    .bind(media)
    .bind(account)
    .bind(&key)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload)
         values ($1, $2, $3, $4, jsonb_build_object(
             'itemId', $5::text, 'mediaId', $4,
             'model', 'a/model', 'promptVersion', 'p1', 'styleVersion', 'v1'))",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(wardrobe_db::STYLISE_ILLUSTRATION)
    .bind(media.to_string())
    .bind(item.to_string())
    .execute(pool)
    .await?;

    sqlx::query("update account set change_seq = 1 where id = $1")
        .bind(account)
        .execute(pool)
        .await?;

    Ok(Scene {
        account,
        item,
        media,
    })
}

async fn run(pool: &PgPool) -> Outcome {
    let storage = store();
    run_one(pool, wardrobe_db::STYLISE_ILLUSTRATION, |job| async move {
        illustration::stylise_for(pool, &storage, &job).await
    })
    .await
    .expect("the claim itself works")
    .expect("a job was waiting")
}

async fn state_of(pool: &PgPool, item: Uuid) -> (String, Option<Uuid>) {
    sqlx::query_as(
        "select illustration_state, current_illustration_id from wardrobe_item where id = $1",
    )
    .bind(item)
    .fetch_one(pool)
    .await
    .expect("the item")
}

async fn versions(pool: &PgPool, item: Uuid) -> Vec<(Uuid, Uuid, String, String, String)> {
    sqlx::query_as(
        "select id, media_object_id, style_version, model, prompt_version
           from item_illustration where item_id = $1",
    )
    .bind(item)
    .fetch_all(pool)
    .await
    .expect("versions")
}

// -------------------------------------------------------------------- the loop

#[sqlx::test(migrations = "../../migrations")]
async fn a_generation_becomes_an_immutable_ready_illustration(pool: PgPool) -> sqlx::Result<()> {
    let scene = scene(&pool, a_garment()).await?;

    assert_eq!(run(&pool).await, Outcome::Succeeded);

    let (state, current) = state_of(&pool, scene.item).await;
    assert_eq!(state, "ready");
    let stored = versions(&pool, scene.item).await;
    assert_eq!(stored.len(), 1);
    let (version, media, style, model, prompt) = stored[0].clone();
    assert_eq!(
        current,
        Some(version),
        "the item has to point at the version this run created"
    );
    assert_eq!(
        (style.as_str(), model.as_str(), prompt.as_str()),
        ("v1", "a/model", "p1")
    );
    assert_ne!(media, scene.media, "the styled asset is its own object");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_stored_asset_is_a_transparent_rgba_png(pool: PgPool) -> sqlx::Result<()> {
    let scene = scene(&pool, a_garment()).await?;

    run(&pool).await;

    let key: String = sqlx::query_scalar(
        "select m.storage_key from item_illustration i
           join media_object m on m.id = i.media_object_id
          where i.item_id = $1",
    )
    .bind(scene.item)
    .fetch_one(&pool)
    .await?;
    let bytes = store().get(&key).await.expect("the styled asset");

    let styled = image::load_from_memory(&bytes).expect("a png").to_rgba8();
    assert_eq!(styled.dimensions(), (256, 256));
    assert_eq!(
        styled.get_pixel(1, 1)[3],
        0,
        "the corner has to be transparent, or it is not a sticker"
    );
    assert_eq!(styled.get_pixel(128, 128)[3], 255);
    let _ = scene.account;
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_mask_that_fails_inspection_leaves_the_cutout_in_charge(
    pool: PgPool,
) -> sqlx::Result<()> {
    let scene = scene(&pool, generation(256, &[(0, 80, 120, 90)])).await?;

    assert_eq!(run(&pool).await, Outcome::Succeeded);

    let (state, current) = state_of(&pool, scene.item).await;
    assert_eq!(state, "failed");
    assert_eq!(current, None);
    assert!(
        versions(&pool, scene.item).await.is_empty(),
        "a refused mask never becomes a stored version"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn bytes_that_are_not_an_image_leave_the_cutout_in_charge(pool: PgPool) -> sqlx::Result<()> {
    let scene = scene(&pool, b"not an image".to_vec()).await?;

    assert_eq!(run(&pool).await, Outcome::Succeeded);

    assert_eq!(state_of(&pool, scene.item).await.0, "failed");
    assert!(versions(&pool, scene.item).await.is_empty());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_database_failure_after_the_object_lands_never_shows_as_ready(
    pool: PgPool,
) -> sqlx::Result<()> {
    let scene = scene(&pool, a_garment()).await?;
    sqlx::query("alter table item_illustration add constraint refuse check (false) not valid")
        .execute(&pool)
        .await?;
    sqlx::query("alter table item_illustration validate constraint refuse")
        .execute(&pool)
        .await
        .ok();

    run(&pool).await;

    let (state, current) = state_of(&pool, scene.item).await;
    assert_ne!(
        state, "ready",
        "a half-written publish must never read as ready"
    );
    assert_eq!(current, None);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_new_illustration_carries_its_own_feed_position(pool: PgPool) -> sqlx::Result<()> {
    let scene = scene(&pool, a_garment()).await?;

    run(&pool).await;

    let (version_seq, item_seq): (i64, i64) = sqlx::query_as(
        "select i.change_seq, w.change_seq from item_illustration i
           join wardrobe_item w on w.id = i.item_id
          where i.item_id = $1",
    )
    .bind(scene.item)
    .fetch_one(&pool)
    .await?;
    assert!(version_seq > 1, "the client learns about it from the feed");
    assert_eq!(version_seq, item_seq);
    Ok(())
}

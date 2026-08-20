mod common;

use std::collections::BTreeSet;

use axum::http::StatusCode;
use chrono::{Duration, Utc};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call, get, get_with_auth, session};

// ------------------------------------------------------------------- fixtures

async fn pull(pool: &PgPool, token: &str, query: &str) -> Value {
    let response = call(
        pool.clone(),
        get_with_auth(&format!("/v1/changes{query}"), &format!("Bearer {token}")),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    body_json(response).await
}

fn kinds(page: &Value) -> Vec<String> {
    page["changes"]
        .as_array()
        .expect("an array of changes")
        .iter()
        .map(|change| change["kind"].as_str().expect("a kind").to_owned())
        .collect()
}

fn positions(page: &Value) -> Vec<i64> {
    page["changes"]
        .as_array()
        .expect("an array of changes")
        .iter()
        .map(|change| change["changeSeq"].as_i64().expect("a position"))
        .collect()
}

struct Seeded {
    item: Uuid,
}

struct Base {
    media: Uuid,
    card: Uuid,
    item: Uuid,
    photo: Uuid,
    derivative: Uuid,
}

async fn seed_base(pool: &PgPool, account: Uuid) -> sqlx::Result<Base> {
    let media = Uuid::now_v7();
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, 'original', $3, 'image/jpeg')",
    )
    .bind(media)
    .bind(account)
    .bind(format!("k/{media}"))
    .execute(pool)
    .await?;

    let card = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_card (id, source, prompt_text, locale)
         values ($1, 'curated', 'Wear something blue', 'en')",
    )
    .bind(card)
    .execute(pool)
    .await?;

    let item = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq)
         values ($1, $2, 'top', 1)",
    )
    .bind(item)
    .bind(account)
    .execute(pool)
    .await?;

    let photo = Uuid::now_v7();
    sqlx::query(
        "insert into photo (id, account_id, media_object_id, source, change_seq)
         values ($1, $2, $3, 'capture', 2)",
    )
    .bind(photo)
    .bind(account)
    .bind(media)
    .execute(pool)
    .await?;

    let derivative = Uuid::now_v7();
    sqlx::query(
        "insert into photo_derivative (id, account_id, photo_id, media_object_id, change_seq)
         values ($1, $2, $3, $4, 3)",
    )
    .bind(derivative)
    .bind(account)
    .bind(photo)
    .bind(media)
    .execute(pool)
    .await?;

    Ok(Base {
        media,
        card,
        item,
        photo,
        derivative,
    })
}

async fn seed_item_details(pool: &PgPool, account: Uuid, base: &Base) -> sqlx::Result<()> {
    sqlx::query(
        "insert into item_fingerprint
             (id, account_id, item_id, version, color_lab, aspect_ratio, feature_print,
              mask_quality, source_photo_id, change_seq)
         values ($1, $2, $3, 'v1', $4, 0.75, $5, 0.9, $6, 4)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(vec![50.0_f32, 10.0, -20.0])
    .bind(vec![1_u8, 2, 3, 4])
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into item_cutout
             (id, account_id, item_id, media_object_id, source_photo_id, change_seq)
         values ($1, $2, $3, $4, $5, 5)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(base.media)
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into item_illustration
             (id, account_id, item_id, media_object_id, style_version, model,
              prompt_version, change_seq)
         values ($1, $2, $3, $4, 's1', 'a-model', 'p1', 6)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(base.media)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into wardrobe_item_conflict
             (id, account_id, item_id, field, value, revision, change_seq)
         values ($1, $2, $3, 'name', 'Blue shirt', 2, 11)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .execute(pool)
    .await?;

    Ok(())
}

async fn seed_loop(pool: &PgPool, account: Uuid, base: &Base) -> sqlx::Result<()> {
    let completion = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_completion
             (id, account_id, card_id, local_date, time_zone, completed_at, status,
              photo_id, current_derivative_id, change_seq)
         values ($1, $2, $3, current_date, 'Asia/Jakarta', now(), 'canonical', $4, $5, 7)",
    )
    .bind(completion)
    .bind(account)
    .bind(base.card)
    .bind(base.photo)
    .bind(base.derivative)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into active_challenge
             (id, account_id, card_id, accepted_at, local_date, time_zone, photo_id, change_seq)
         values ($1, $2, $3, now(), current_date, 'Asia/Jakarta', $4, 8)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.card)
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into wear_record
             (id, account_id, item_id, completion_id, source_photo_id, worn_on, change_seq)
         values ($1, $2, $3, $4, $5, current_date, 9)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(base.item)
    .bind(completion)
    .bind(base.photo)
    .execute(pool)
    .await?;

    sqlx::query(
        "insert into canvas_document
             (id, account_id, completion_id, derivative_id, schema_version,
              media_object_id, change_seq)
         values ($1, $2, $3, $4, 1, $5, 10)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(completion)
    .bind(base.derivative)
    .bind(base.media)
    .execute(pool)
    .await?;

    sqlx::query("insert into account_preference (account_id, change_seq) values ($1, 12)")
        .bind(account)
        .execute(pool)
        .await?;

    Ok(())
}

async fn seed_every_kind(pool: &PgPool, account: Uuid) -> sqlx::Result<Seeded> {
    let base = seed_base(pool, account).await?;
    seed_item_details(pool, account, &base).await?;
    seed_loop(pool, account, &base).await?;
    Ok(Seeded { item: base.item })
}

// ------------------------------------------------------------------- coverage

#[sqlx::test(migrations = "../../migrations")]
async fn every_synced_kind_reaches_the_feed(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    seed_every_kind(&pool, account).await?;

    let page = pull(&pool, &token, "").await;
    let seen: BTreeSet<String> = kinds(&page).into_iter().collect();

    assert_eq!(
        seen.len(),
        wardrobe_api::changes::SYNCED_TABLES.len(),
        "a kind missing from the feed is data the client can never learn about; got {seen:?}"
    );
    assert_eq!(page["nextSince"], 12);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn no_table_with_a_cursor_column_is_left_out_of_the_feed(pool: PgPool) -> sqlx::Result<()> {
    let carries_cursor: Vec<String> = sqlx::query_scalar(
        "select table_name from information_schema.columns
          where table_schema = 'public' and column_name = 'change_seq'",
    )
    .fetch_all(&pool)
    .await?;

    let mut expected: BTreeSet<&str> = wardrobe_api::changes::SYNCED_TABLES
        .iter()
        .copied()
        .collect();
    expected.insert("account");

    let found: BTreeSet<&str> = carries_cursor.iter().map(String::as_str).collect();
    assert_eq!(
        found, expected,
        "`account` is excluded because its change_seq hands out positions rather than being one; \
         every other table with the column needs a branch in changes.rs"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn no_record_carries_an_object_key(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    seed_every_kind(&pool, account).await?;

    let page = pull(&pool, &token, "").await;
    let text = page.to_string();
    assert!(
        !text.contains("storageKey") && !text.contains("storage_key"),
        "the client never sees an object key; a signed URL is a grant, not an identity"
    );
    Ok(())
}

// -------------------------------------------------------------------- ordering

#[sqlx::test(migrations = "../../migrations")]
async fn rows_written_together_all_appear_in_position_order(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    seed_every_kind(&pool, account).await?;

    let page = pull(&pool, &token, "").await;
    let mut sorted = positions(&page);
    sorted.sort_unstable();
    assert_eq!(positions(&page), sorted, "the feed is ordered by position");
    assert_eq!(positions(&page), (1..=12).collect::<Vec<_>>());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_tombstone_travels_the_feed_like_any_other_record(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let seeded = seed_every_kind(&pool, account).await?;

    sqlx::query("update wardrobe_item set deleted_at = now(), change_seq = 20 where id = $1")
        .bind(seeded.item)
        .execute(&pool)
        .await?;

    let page = pull(&pool, &token, "?since=12").await;
    let changes = page["changes"].as_array().expect("changes");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0]["kind"], "wardrobeItem");
    assert!(
        !changes[0]["record"]["deletedAt"].is_null(),
        "a deletion the feed omits is a row that lives forever on every other device"
    );
    Ok(())
}

// --------------------------------------------------------------------- paging

#[sqlx::test(migrations = "../../migrations")]
async fn walking_the_feed_one_row_at_a_time_skips_nothing(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    seed_every_kind(&pool, account).await?;

    let mut cursor = 0;
    let mut walked = Vec::new();
    loop {
        let page = pull(&pool, &token, &format!("?since={cursor}&limit=1")).await;
        let batch = positions(&page);
        if batch.is_empty() {
            break;
        }
        walked.extend(batch);
        cursor = page["nextSince"].as_i64().expect("a cursor");
    }

    assert_eq!(walked, (1..=12).collect::<Vec<_>>());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_empty_page_leaves_the_cursor_where_it_was(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    seed_every_kind(&pool, account).await?;

    let page = pull(&pool, &token, "?since=99").await;
    assert!(page["changes"].as_array().expect("changes").is_empty());
    assert_eq!(
        page["nextSince"], 99,
        "an empty page must not jump the cursor to the account counter"
    );
    Ok(())
}

// -------------------------------------------------------------- authorization

#[sqlx::test(migrations = "../../migrations")]
async fn another_accounts_rows_never_appear(pool: PgPool) -> sqlx::Result<()> {
    let (mine, _) = session(&pool, Duration::days(1), false).await?;
    let (_, theirs) = session(&pool, Duration::days(1), false).await?;
    seed_every_kind(&pool, theirs).await?;

    let page = pull(&pool, &mine, "").await;
    assert!(page["changes"].as_array().expect("changes").is_empty());
    assert_eq!(page["nextSince"], 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_feed_without_a_token_is_unauthenticated(pool: PgPool) {
    let response = call(pool, get("/v1/changes")).await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_expired_token_cannot_read_the_feed(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, -Duration::days(1), false).await?;
    seed_every_kind(&pool, account).await?;

    let response = call(
        pool.clone(),
        get_with_auth("/v1/changes", &format!("Bearer {token}")),
    )
    .await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    let _ = Utc::now();
    Ok(())
}

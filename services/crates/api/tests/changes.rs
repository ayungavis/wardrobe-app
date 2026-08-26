mod common;

use std::collections::BTreeSet;

use axum::http::StatusCode;
use chrono::Duration;
use serde_json::Value;
use sqlx::PgPool;

use common::{body_json, call, get, get_with_auth, seed_every_kind, session};

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
    Ok(())
}

mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use chrono::Duration;
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call, get_with_auth, session};

// ------------------------------------------------------------------- fixtures

fn field(value: &str, rev: i64) -> Value {
    json!({ "value": value, "rev": rev })
}

async fn upsert(pool: &PgPool, token: &str, args: &Value) -> Value {
    let request = Request::builder()
        .method("POST")
        .uri("/v1/sync")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(
            json!({ "mutations": [{
                "id": Uuid::now_v7(), "name": "upsertItem", "args": args
            }]})
            .to_string(),
        ))
        .expect("request");
    let response = call(pool.clone(), request).await;
    assert_eq!(response.status(), StatusCode::OK);
    body_json(response).await["results"][0].clone()
}

async fn on_a_device(pool: &PgPool) -> sqlx::Result<(String, Uuid, Uuid)> {
    let (token, account) = session(pool, Duration::days(1), false).await?;
    let device = Uuid::now_v7();
    sqlx::query(
        "insert into account_device (anonymous_id, account_id, last_seen_at)
         values ($1, $2, now())",
    )
    .bind(device)
    .bind(account)
    .execute(pool)
    .await?;
    sqlx::query("update session set device_id = $2 where account_id = $1")
        .bind(account)
        .bind(device)
        .execute(pool)
        .await?;
    Ok((token, account, device))
}

async fn values_of(pool: &PgPool, item: Uuid) -> (String, Option<String>, Option<String>) {
    sqlx::query_as("select category, name, color from wardrobe_item where id = $1")
        .bind(item)
        .fetch_one(pool)
        .await
        .expect("the item row")
}

async fn change_seq(pool: &PgPool, account: Uuid) -> i64 {
    sqlx::query_scalar("select change_seq from account where id = $1")
        .bind(account)
        .fetch_one(pool)
        .await
        .expect("counter")
}

// -------------------------------------------------------------------- merging

#[sqlx::test(migrations = "../../migrations")]
async fn two_devices_editing_different_fields_both_keep_their_edit(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let item = Uuid::now_v7();
    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("top", 1) }),
    )
    .await;

    upsert(
        &pool,
        &token,
        &json!({ "id": item, "name": field("Blue shirt", 1) }),
    )
    .await;
    upsert(
        &pool,
        &token,
        &json!({ "id": item, "color": field("blue", 1) }),
    )
    .await;

    let (category, name, color) = values_of(&pool, item).await;
    assert_eq!(category, "top");
    assert_eq!(name.as_deref(), Some("Blue shirt"));
    assert_eq!(
        color.as_deref(),
        Some("blue"),
        "edits that do not overlap must both survive"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_same_revision_with_a_different_value_becomes_a_conflict(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, account, device) = on_a_device(&pool).await?;
    let item = Uuid::now_v7();
    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("top", 1), "name": field("Mine", 2) }),
    )
    .await;

    let result = upsert(
        &pool,
        &token,
        &json!({ "id": item, "name": field("Theirs", 2) }),
    )
    .await;

    assert_eq!(
        result["status"], "applied",
        "a refusal would have the outbox retry forever instead of asking the user"
    );
    assert_eq!(
        values_of(&pool, item).await.1.as_deref(),
        Some("Mine"),
        "recording a conflict while quietly overwriting the value is the failure that hides"
    );

    let conflict: (String, Option<String>, i64, Option<Uuid>) = sqlx::query_as(
        "select field, value, revision, origin_device from wardrobe_item_conflict
          where item_id = $1",
    )
    .bind(item)
    .fetch_one(&pool)
    .await?;
    assert_eq!(conflict.0, "name");
    assert_eq!(conflict.1.as_deref(), Some("Theirs"));
    assert_eq!(conflict.2, 2);
    assert_eq!(
        conflict.3,
        Some(device),
        "the origin is a fact the server already holds; the body never gets to claim it"
    );
    let _ = account;
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_older_revision_loses_quietly(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let item = Uuid::now_v7();
    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("top", 1), "name": field("Newer", 5) }),
    )
    .await;

    upsert(
        &pool,
        &token,
        &json!({ "id": item, "name": field("Older", 2) }),
    )
    .await;

    assert_eq!(values_of(&pool, item).await.1.as_deref(), Some("Newer"));
    let conflicts: i64 =
        sqlx::query_scalar("select count(*) from wardrobe_item_conflict where item_id = $1")
            .bind(item)
            .fetch_one(&pool)
            .await?;
    assert_eq!(conflicts, 0, "a stale edit is not a disagreement");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn category_follows_the_same_rule_as_every_other_field(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let item = Uuid::now_v7();
    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("top", 1) }),
    )
    .await;

    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("outerwear", 2) }),
    )
    .await;
    assert_eq!(values_of(&pool, item).await.0, "outerwear");

    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("footwear", 2) }),
    )
    .await;
    assert_eq!(
        values_of(&pool, item).await.0,
        "outerwear",
        "the conflict table has allowed a category row since the first migration"
    );
    let field_named: String =
        sqlx::query_scalar("select field from wardrobe_item_conflict where item_id = $1")
            .bind(item)
            .fetch_one(&pool)
            .await?;
    assert_eq!(field_named, "category");
    Ok(())
}

// ---------------------------------------------------------------- idempotency

#[sqlx::test(migrations = "../../migrations")]
async fn repeating_the_same_upsert_moves_no_cursor(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let item = Uuid::now_v7();
    let args = json!({ "id": item, "category": field("top", 1), "name": field("Blue shirt", 1) });

    upsert(&pool, &token, &args).await;
    let settled = change_seq(&pool, account).await;
    upsert(&pool, &token, &args).await;

    assert_eq!(
        change_seq(&pool, account).await,
        settled,
        "a retry that advances the feed makes every reconnection look like new work"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_upsert_cannot_revive_a_tombstoned_item(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let item = Uuid::now_v7();
    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("top", 1), "name": field("Gone", 1) }),
    )
    .await;
    sqlx::query("update wardrobe_item set deleted_at = now() where id = $1")
        .bind(item)
        .execute(&pool)
        .await?;

    upsert(
        &pool,
        &token,
        &json!({ "id": item, "name": field("Back", 9) }),
    )
    .await;

    assert_eq!(
        values_of(&pool, item).await.1.as_deref(),
        Some("Gone"),
        "a tombstone outranks an ordinary edit"
    );
    Ok(())
}

// -------------------------------------------------------- new items and jobs

#[sqlx::test(migrations = "../../migrations")]
async fn a_new_item_is_enqueued_once_and_an_edit_never_is(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let item = Uuid::now_v7();

    upsert(
        &pool,
        &token,
        &json!({ "id": item, "category": field("top", 1) }),
    )
    .await;
    upsert(
        &pool,
        &token,
        &json!({ "id": item, "name": field("Blue shirt", 1) }),
    )
    .await;

    let jobs: i64 = sqlx::query_scalar("select count(*) from job where kind = 'illustration'")
        .fetch_one(&pool)
        .await?;
    assert_eq!(jobs, 1, "an edit is not a new garment to render");

    let state: String =
        sqlx::query_scalar("select illustration_state from wardrobe_item where id = $1")
            .bind(item)
            .fetch_one(&pool)
            .await?;
    assert_eq!(state, "queued");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_item_added_outside_the_daily_loop_can_carry_its_cutout(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let media = Uuid::now_v7();
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, 'cutout', $3, 'image/png')",
    )
    .bind(media)
    .bind(account)
    .bind(format!("k/{media}"))
    .execute(&pool)
    .await?;

    let item = Uuid::now_v7();
    let cutout = Uuid::now_v7();
    upsert(
        &pool,
        &token,
        &json!({
            "id": item, "category": field("top", 1),
            "cutout": { "id": cutout, "mediaObjectId": media }
        }),
    )
    .await;

    let owner: Uuid = sqlx::query_scalar("select item_id from item_cutout where id = $1")
        .bind(cutout)
        .fetch_one(&pool)
        .await?;
    assert_eq!(owner, item);

    let feed = body_json(
        call(
            pool.clone(),
            get_with_auth("/v1/changes?since=0", &format!("Bearer {token}")),
        )
        .await,
    )
    .await;
    let kinds: Vec<&str> = feed["changes"]
        .as_array()
        .expect("changes")
        .iter()
        .map(|change| change["kind"].as_str().expect("kind"))
        .collect();
    assert!(
        kinds.contains(&"itemCutout"),
        "add-by-photos produces a cut-out with no completion behind it: {kinds:?}"
    );
    Ok(())
}

// ---------------------------------------------------------------- boundaries

#[sqlx::test(migrations = "../../migrations")]
async fn a_new_item_without_a_category_is_a_client_error(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;

    let result = upsert(
        &pool,
        &token,
        &json!({ "id": Uuid::now_v7(), "name": field("Nameless", 1) }),
    )
    .await;

    assert_eq!(result["status"], "failed");
    assert_eq!(result["error"]["code"], "bad_request");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_accounts_item_id_is_a_conflict(pool: PgPool) -> sqlx::Result<()> {
    let (mine, _) = session(&pool, Duration::days(1), false).await?;
    let (theirs, _) = session(&pool, Duration::days(1), false).await?;
    let item = Uuid::now_v7();
    upsert(
        &pool,
        &theirs,
        &json!({ "id": item, "category": field("top", 1) }),
    )
    .await;

    let result = upsert(
        &pool,
        &mine,
        &json!({ "id": item, "name": field("Mine", 1) }),
    )
    .await;

    assert_eq!(result["error"]["code"], "conflict");
    Ok(())
}

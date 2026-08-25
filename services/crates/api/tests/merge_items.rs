mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use chrono::Duration;
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call, session};

// ------------------------------------------------------------------- fixtures

async fn merge(pool: &PgPool, token: &str, winner: Uuid, loser: Uuid) -> Value {
    let request = Request::builder()
        .method("POST")
        .uri("/v1/sync")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(
            json!({ "mutations": [{
                "id": Uuid::now_v7(), "name": "mergeItems",
                "args": { "winnerId": winner, "loserId": loser }
            }]})
            .to_string(),
        ))
        .expect("request");
    let response = call(pool.clone(), request).await;
    assert_eq!(response.status(), StatusCode::OK);
    body_json(response).await["results"][0].clone()
}

async fn seed_item(pool: &PgPool, account: Uuid) -> sqlx::Result<Uuid> {
    let item = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq)
         values ($1, $2, 'top', 1)",
    )
    .bind(item)
    .bind(account)
    .execute(pool)
    .await?;
    Ok(item)
}

async fn seed_photo(pool: &PgPool, account: Uuid) -> sqlx::Result<Uuid> {
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
    Ok(photo)
}

async fn seed_wear(
    pool: &PgPool,
    account: Uuid,
    item: Uuid,
    photo: Option<Uuid>,
) -> sqlx::Result<Uuid> {
    let wear = Uuid::now_v7();
    sqlx::query(
        "insert into wear_record
             (id, account_id, item_id, completion_id, source_photo_id, worn_on, change_seq)
         values ($1, $2, $3, null, $4, current_date, 5)",
    )
    .bind(wear)
    .bind(account)
    .bind(item)
    .bind(photo)
    .execute(pool)
    .await?;
    Ok(wear)
}

async fn seed_fingerprint(pool: &PgPool, account: Uuid, item: Uuid) -> sqlx::Result<Uuid> {
    let fingerprint = Uuid::now_v7();
    sqlx::query(
        "insert into item_fingerprint
             (id, account_id, item_id, version, color_lab, aspect_ratio, feature_print,
              mask_quality, source_photo_id, change_seq)
         values ($1, $2, $3, 'v1', $4, 0.75, $5, 0.9, null, 4)",
    )
    .bind(fingerprint)
    .bind(account)
    .bind(item)
    .bind(vec![50.0_f32, 10.0, -20.0])
    .bind(vec![1_u8, 2, 3, 4])
    .execute(pool)
    .await?;
    Ok(fingerprint)
}

async fn counter(pool: &PgPool, account: Uuid) -> i64 {
    sqlx::query_scalar("select change_seq from account where id = $1")
        .bind(account)
        .fetch_one(pool)
        .await
        .expect("the account row")
}

async fn live_wears(pool: &PgPool, item: Uuid) -> i64 {
    sqlx::query_scalar("select count(*) from wear_record where item_id = $1 and deleted_at is null")
        .bind(item)
        .fetch_one(pool)
        .await
        .expect("a count")
}

// ---------------------------------------------------------------------- tests

#[sqlx::test(migrations = "../../migrations")]
async fn a_merge_moves_wears_and_fingerprints_to_the_survivor(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;
    seed_wear(&pool, account, loser, None).await?;
    let fingerprint = seed_fingerprint(&pool, account, loser).await?;

    let result = merge(&pool, &token, winner, loser).await;

    assert_eq!(result["status"], "applied");
    assert_eq!(live_wears(&pool, winner).await, 1, "the wear moved");
    assert_eq!(live_wears(&pool, loser).await, 0);
    let owner: Uuid = sqlx::query_scalar("select item_id from item_fingerprint where id = $1")
        .bind(fingerprint)
        .fetch_one(&pool)
        .await?;
    assert_eq!(
        owner, winner,
        "the fingerprint set unions into the survivor"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn colliding_wears_are_dropped_not_duplicated(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;
    let photo = seed_photo(&pool, account).await?;
    seed_wear(&pool, account, winner, Some(photo)).await?;
    let losing_wear = seed_wear(&pool, account, loser, Some(photo)).await?;

    let result = merge(&pool, &token, winner, loser).await;

    assert_eq!(result["status"], "applied");
    assert_eq!(
        live_wears(&pool, winner).await,
        1,
        "the same item and source photo can never carry two wears (FR-064)"
    );
    let buried: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("select deleted_at from wear_record where id = $1")
            .bind(losing_wear)
            .fetch_one(&pool)
            .await?;
    assert!(
        buried.is_some(),
        "the loser's duplicate is tombstoned, not moved"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_loser_is_tombstoned_not_deleted(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;

    merge(&pool, &token, winner, loser).await;

    let (deleted_at,): (Option<chrono::DateTime<chrono::Utc>>,) =
        sqlx::query_as("select deleted_at from wardrobe_item where id = $1")
            .bind(loser)
            .fetch_one(&pool)
            .await?;
    assert!(
        deleted_at.is_some(),
        "the row survives as a tombstone so an offline device cannot resurrect it"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_replay_allocates_no_change_position(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;
    seed_wear(&pool, account, loser, None).await?;

    merge(&pool, &token, winner, loser).await;
    let after_first = counter(&pool, account).await;
    let replay = merge(&pool, &token, winner, loser).await;

    assert_eq!(replay["status"], "applied");
    assert_eq!(
        counter(&pool, account).await,
        after_first,
        "a replay must not allocate a change position, or every retry would grow the feed"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn moved_rows_take_fresh_feed_positions(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;
    let fingerprint = seed_fingerprint(&pool, account, loser).await?;
    let before = counter(&pool, account).await;

    merge(&pool, &token, winner, loser).await;

    let seq: i64 = sqlx::query_scalar("select change_seq from item_fingerprint where id = $1")
        .bind(fingerprint)
        .fetch_one(&pool)
        .await?;
    assert!(
        seq > before,
        "a cursor already past the old position must still see the move"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_losers_illustration_wins_when_the_winner_has_none(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;
    let media = Uuid::now_v7();
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, 'illustration', $3, 'image/png')",
    )
    .bind(media)
    .bind(account)
    .bind(format!("k/{media}"))
    .execute(&pool)
    .await?;
    let illustration = Uuid::now_v7();
    sqlx::query(
        "insert into item_illustration
             (id, account_id, item_id, media_object_id, style_version, model, prompt_version, change_seq)
         values ($1, $2, $3, $4, 's1', 'm1', 'p1', 6)",
    )
    .bind(illustration)
    .bind(account)
    .bind(loser)
    .bind(media)
    .execute(&pool)
    .await?;
    sqlx::query("update wardrobe_item set current_illustration_id = $2 where id = $1")
        .bind(loser)
        .bind(illustration)
        .execute(&pool)
        .await?;

    merge(&pool, &token, winner, loser).await;

    let adopted: Option<Uuid> =
        sqlx::query_scalar("select current_illustration_id from wardrobe_item where id = $1")
            .bind(winner)
            .fetch_one(&pool)
            .await?;
    assert_eq!(adopted, Some(illustration), "one illustration wins");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn merging_an_item_into_itself_is_refused(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let item = seed_item(&pool, account).await?;

    let result = merge(&pool, &token, item, item).await;

    assert_eq!(result["status"], "failed");
    assert_eq!(result["error"]["code"], "bad_request");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn someone_elses_item_is_not_found(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let (_, stranger) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let other = seed_item(&pool, stranger).await?;

    let result = merge(&pool, &token, winner, other).await;

    assert_eq!(result["status"], "failed");
    assert_eq!(result["error"]["code"], "not_found");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_tombstoned_winner_is_refused(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;
    sqlx::query("update wardrobe_item set deleted_at = now() where id = $1")
        .bind(winner)
        .execute(&pool)
        .await?;

    let result = merge(&pool, &token, winner, loser).await;

    assert_eq!(result["status"], "failed");
    assert_eq!(result["error"]["code"], "bad_request");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_losers_open_conflicts_are_resolved(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let winner = seed_item(&pool, account).await?;
    let loser = seed_item(&pool, account).await?;
    let conflict = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item_conflict (id, account_id, item_id, field, value, revision, change_seq)
         values ($1, $2, $3, 'name', 'x', 1, 5)",
    )
    .bind(conflict)
    .bind(account)
    .bind(loser)
    .execute(&pool)
    .await?;

    merge(&pool, &token, winner, loser).await;

    let resolved: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("select resolved_at from wardrobe_item_conflict where id = $1")
            .bind(conflict)
            .fetch_one(&pool)
            .await?;
    assert!(
        resolved.is_some(),
        "a buried item has nothing left to decide"
    );
    Ok(())
}

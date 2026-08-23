mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use chrono::Duration;
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call, session};

// ------------------------------------------------------------------- fixtures

struct Stage {
    token: String,
    account: Uuid,
    media: Uuid,
    card: Uuid,
}

async fn stage(pool: &PgPool) -> sqlx::Result<Stage> {
    let (token, account) = session(pool, Duration::days(1), false).await?;
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

    Ok(Stage {
        token,
        account,
        media,
        card,
    })
}

struct Ticket {
    completion: Uuid,
    photo: Uuid,
    item: Uuid,
    wear: Uuid,
}

fn fresh() -> Ticket {
    Ticket {
        completion: Uuid::now_v7(),
        photo: Uuid::now_v7(),
        item: Uuid::now_v7(),
        wear: Uuid::now_v7(),
    }
}

fn args(stage: &Stage, ticket: &Ticket, local_date: &str) -> Value {
    json!({
        "completionId": ticket.completion,
        "cardId": stage.card,
        "localDate": local_date,
        "timeZone": "Asia/Jakarta",
        "completedAt": "2026-08-21T10:00:00Z",
        "photo": {
            "id": ticket.photo,
            "mediaObjectId": stage.media,
            "source": "capture",
            "capturedAt": "2026-08-21T09:55:00Z"
        },
        "derivative": { "id": Uuid::now_v7(), "mediaObjectId": stage.media },
        "document": {
            "id": Uuid::now_v7(),
            "schemaVersion": 1,
            "mediaObjectId": stage.media,
            "historyStepCount": 4
        },
        "items": [{
            "id": ticket.item,
            "wearId": ticket.wear,
            "category": "top",
            "name": "Blue shirt",
            "sourcePhotoId": ticket.photo
        }]
    })
}

async fn complete(pool: &PgPool, stage: &Stage, body: &Value) -> Value {
    let request = Request::builder()
        .method("POST")
        .uri("/v1/sync")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {}", stage.token))
        .body(Body::from(
            json!({ "mutations": [{
                "id": Uuid::now_v7(), "name": "completeChallenge", "args": body
            }]})
            .to_string(),
        ))
        .expect("request");
    let response = call(pool.clone(), request).await;
    assert_eq!(response.status(), StatusCode::OK);
    body_json(response).await["results"][0].clone()
}

async fn count(pool: &PgPool, table: &str, account: Uuid) -> i64 {
    sqlx::query_scalar(&format!(
        "select count(*) from {table} where account_id = $1"
    ))
    .bind(account)
    .fetch_one(pool)
    .await
    .expect("count")
}

async fn change_seq(pool: &PgPool, account: Uuid) -> i64 {
    sqlx::query_scalar("select change_seq from account where id = $1")
        .bind(account)
        .fetch_one(pool)
        .await
        .expect("counter")
}

// ------------------------------------------------------------------ the check

#[sqlx::test(migrations = "../../migrations")]
async fn one_check_writes_every_artefact_and_the_feed_returns_them(
    pool: PgPool,
) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();

    let result = complete(&pool, &stage, &args(&stage, &ticket, "2026-08-21")).await;
    assert_eq!(result["status"], "applied");
    assert_eq!(result["record"]["status"], "canonical");

    for table in [
        "challenge_completion",
        "photo",
        "photo_derivative",
        "canvas_document",
        "wardrobe_item",
        "wear_record",
    ] {
        assert_eq!(count(&pool, table, stage.account).await, 1, "{table}");
    }
    let links: i64 =
        sqlx::query_scalar("select count(*) from completion_photo where completion_id = $1")
            .bind(ticket.completion)
            .fetch_one(&pool)
            .await?;
    assert_eq!(links, 1);

    let response = call(
        pool.clone(),
        Request::builder()
            .uri("/v1/changes?since=0")
            .header("authorization", format!("Bearer {}", stage.token))
            .body(Body::empty())
            .expect("request"),
    )
    .await;
    let feed = body_json(response).await;
    let kinds: Vec<&str> = feed["changes"]
        .as_array()
        .expect("changes")
        .iter()
        .map(|change| change["kind"].as_str().expect("kind"))
        .collect();
    for kind in [
        "photo",
        "photoDerivative",
        "challengeCompletion",
        "canvasDocument",
        "wardrobeItem",
        "wearRecord",
    ] {
        assert!(kinds.contains(&kind), "the feed dropped {kind}: {kinds:?}");
    }
    Ok(())
}

// ------------------------------------------------------------------- conflict

#[sqlx::test(migrations = "../../migrations")]
async fn a_second_completion_for_the_same_local_day_is_conflicting(
    pool: PgPool,
) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;

    let first = complete(&pool, &stage, &args(&stage, &fresh(), "2026-08-21")).await;
    let second_ticket = fresh();
    let second = complete(&pool, &stage, &args(&stage, &second_ticket, "2026-08-21")).await;

    assert_eq!(first["record"]["status"], "canonical");
    assert_eq!(
        second["record"]["status"], "conflicting",
        "the earliest completion of a local day stays canonical"
    );

    let kept: Option<Uuid> =
        sqlx::query_scalar("select photo_id from challenge_completion where id = $1")
            .bind(second_ticket.completion)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        kept,
        Some(second_ticket.photo),
        "neither photo is deleted during a conflict"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_different_local_day_is_canonical_again(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    complete(&pool, &stage, &args(&stage, &fresh(), "2026-08-21")).await;
    let next = complete(&pool, &stage, &args(&stage, &fresh(), "2026-08-22")).await;
    assert_eq!(next["record"]["status"], "canonical");
    Ok(())
}

// ------------------------------------------------------------------- replaying

#[sqlx::test(migrations = "../../migrations")]
async fn replaying_a_check_changes_nothing_at_all(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();
    let body = args(&stage, &ticket, "2026-08-21");

    let first = complete(&pool, &stage, &body).await;
    let settled = change_seq(&pool, stage.account).await;

    let again = complete(&pool, &stage, &body).await;
    assert_eq!(again["record"], first["record"]);
    assert_eq!(
        change_seq(&pool, stage.account).await,
        settled,
        "a retry that burns feed positions makes every reconnection look like new work"
    );

    let revision: i32 = sqlx::query_scalar("select revision from wear_record where id = $1")
        .bind(ticket.wear)
        .fetch_one(&pool)
        .await?;
    assert_eq!(
        revision, 1,
        "revising a wear is how a correction is recorded; a retry is not a correction"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn reconfirming_the_same_photo_revises_the_wear_instead_of_adding_one(
    pool: PgPool,
) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let first = fresh();
    complete(&pool, &stage, &args(&stage, &first, "2026-08-21")).await;

    let mut correction = fresh();
    correction.item = first.item;
    let mut body = args(&stage, &correction, "2026-08-22");
    body["items"][0]["sourcePhotoId"] = json!(first.photo);
    complete(&pool, &stage, &body).await;

    assert_eq!(count(&pool, "wear_record", stage.account).await, 1);
    let revision: i32 = sqlx::query_scalar("select revision from wear_record where id = $1")
        .bind(first.wear)
        .fetch_one(&pool)
        .await?;
    assert_eq!(
        revision, 2,
        "a correction revises the wear, never adds a second"
    );
    Ok(())
}

// ----------------------------------------------------------------- atomicity

#[sqlx::test(migrations = "../../migrations")]
async fn a_check_naming_an_unknown_card_leaves_nothing_behind(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let mut body = args(&stage, &fresh(), "2026-08-21");
    body["cardId"] = json!(Uuid::now_v7());

    let result = complete(&pool, &stage, &body).await;
    assert_eq!(result["status"], "failed");
    assert_eq!(
        result["error"]["code"], "bad_request",
        "a bad id is the client's mistake; reporting it as internal tells it to retry forever"
    );

    for table in [
        "challenge_completion",
        "photo",
        "photo_derivative",
        "canvas_document",
        "wardrobe_item",
        "wear_record",
    ] {
        assert_eq!(
            count(&pool, table, stage.account).await,
            0,
            "{table} survived"
        );
    }
    Ok(())
}

// ------------------------------------------------------------ active challenge

#[sqlx::test(migrations = "../../migrations")]
async fn completing_frees_the_slot_the_next_challenge_needs(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    sqlx::query(
        "insert into active_challenge
             (id, account_id, card_id, accepted_at, local_date, time_zone, change_seq)
         values ($1, $2, $3, now(), current_date, 'Asia/Jakarta', 1)",
    )
    .bind(Uuid::now_v7())
    .bind(stage.account)
    .bind(stage.card)
    .execute(&pool)
    .await?;

    complete(&pool, &stage, &args(&stage, &fresh(), "2026-08-21")).await;

    sqlx::query(
        "insert into active_challenge
             (id, account_id, card_id, accepted_at, local_date, time_zone, change_seq)
         values ($1, $2, $3, now(), current_date, 'Asia/Jakarta', 99)",
    )
    .bind(Uuid::now_v7())
    .bind(stage.account)
    .bind(stage.card)
    .execute(&pool)
    .await
    .expect("only one active challenge may live at a time, so the check must free the slot");
    Ok(())
}

// ---------------------------------------------------------------- boundaries

#[sqlx::test(migrations = "../../migrations")]
async fn an_item_that_already_exists_keeps_its_values(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, name, change_seq)
         values ($1, $2, 'outerwear', 'The name I chose', 0)",
    )
    .bind(ticket.item)
    .bind(stage.account)
    .execute(&pool)
    .await?;

    complete(&pool, &stage, &args(&stage, &ticket, "2026-08-21")).await;

    let name: Option<String> = sqlx::query_scalar("select name from wardrobe_item where id = $1")
        .bind(ticket.item)
        .fetch_one(&pool)
        .await?;
    assert_eq!(
        name.as_deref(),
        Some("The name I chose"),
        "merging an existing item's fields is the revision rule's job, not this mutation's"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_accounts_completion_id_is_a_conflict(pool: PgPool) -> sqlx::Result<()> {
    let mine = stage(&pool).await?;
    let theirs = stage(&pool).await?;
    let ticket = fresh();

    complete(&pool, &theirs, &args(&theirs, &ticket, "2026-08-21")).await;

    let mut body = args(&mine, &fresh(), "2026-08-21");
    body["completionId"] = json!(ticket.completion);
    let result = complete(&pool, &mine, &body).await;

    assert_eq!(result["status"], "failed");
    assert_eq!(result["error"]["code"], "conflict");
    Ok(())
}

// --------------------------------------------------------- cut-outs and jobs

fn with_cutout(body: &mut Value, stage: &Stage) -> Uuid {
    let cutout = Uuid::now_v7();
    body["items"][0]["cutout"] = json!({ "id": cutout, "mediaObjectId": stage.media });
    cutout
}

async fn jobs_for(pool: &PgPool, item: Uuid) -> i64 {
    sqlx::query_scalar("select count(*) from job where kind = 'illustration' and dedupe_key = $1")
        .bind(format!("{item}:{}", wardrobe_db::STYLE_VERSION))
        .fetch_one(pool)
        .await
        .expect("count")
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_confirmed_cutout_is_stored_and_reaches_the_feed(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();
    let mut body = args(&stage, &ticket, "2026-08-21");
    let cutout = with_cutout(&mut body, &stage);

    complete(&pool, &stage, &body).await;

    let stored: Uuid = sqlx::query_scalar("select item_id from item_cutout where id = $1")
        .bind(cutout)
        .fetch_one(&pool)
        .await?;
    assert_eq!(stored, ticket.item);

    let response = call(
        pool.clone(),
        Request::builder()
            .uri("/v1/changes?since=0")
            .header("authorization", format!("Bearer {}", stage.token))
            .body(Body::empty())
            .expect("request"),
    )
    .await;
    let feed = body_json(response).await;
    let kinds: Vec<&str> = feed["changes"]
        .as_array()
        .expect("changes")
        .iter()
        .map(|change| change["kind"].as_str().expect("kind"))
        .collect();
    assert!(
        kinds.contains(&"itemCutout"),
        "the cut-out is the one thing the provider may ever see, so a device that never learns of it \
         cannot show what was sent: {kinds:?}"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_genuinely_new_item_gets_exactly_one_illustration_job(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();

    complete(&pool, &stage, &args(&stage, &ticket, "2026-08-21")).await;
    assert_eq!(jobs_for(&pool, ticket.item).await, 1);

    let payload: Value = sqlx::query_scalar("select payload from job where dedupe_key = $1")
        .bind(format!("{}:{}", ticket.item, wardrobe_db::STYLE_VERSION))
        .fetch_one(&pool)
        .await?;
    assert_eq!(payload["itemId"], ticket.item.to_string());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn confirming_an_item_that_already_exists_enqueues_nothing(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq)
         values ($1, $2, 'top', 0)",
    )
    .bind(ticket.item)
    .bind(stage.account)
    .execute(&pool)
    .await?;

    complete(&pool, &stage, &args(&stage, &ticket, "2026-08-21")).await;

    assert_eq!(
        jobs_for(&pool, ticket.item).await,
        0,
        "rendering an illustration for an item that already had one is money spent twice"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn replaying_a_checkmark_enqueues_nothing_new(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();
    let body = args(&stage, &ticket, "2026-08-21");

    complete(&pool, &stage, &body).await;
    complete(&pool, &stage, &body).await;

    assert_eq!(jobs_for(&pool, ticket.item).await, 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_checkmark_without_a_cutout_still_lands_and_still_enqueues(
    pool: PgPool,
) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();

    let result = complete(&pool, &stage, &args(&stage, &ticket, "2026-08-21")).await;
    assert_eq!(result["status"], "applied");

    assert_eq!(count(&pool, "item_cutout", stage.account).await, 0);
    assert_eq!(
        jobs_for(&pool, ticket.item).await,
        1,
        "the illustration waits for its cut-out; it must not hold up the checkmark"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failed_checkmark_leaves_no_cutout_and_no_job(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();
    let mut body = args(&stage, &ticket, "2026-08-21");
    with_cutout(&mut body, &stage);
    body["cardId"] = json!(Uuid::now_v7());

    let result = complete(&pool, &stage, &body).await;
    assert_eq!(result["status"], "failed");

    assert_eq!(count(&pool, "item_cutout", stage.account).await, 0);
    assert_eq!(jobs_for(&pool, ticket.item).await, 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_queued_illustration_is_visible_as_a_pending_state(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();

    complete(&pool, &stage, &args(&stage, &ticket, "2026-08-21")).await;

    let state: String =
        sqlx::query_scalar("select illustration_state from wardrobe_item where id = $1")
            .bind(ticket.item)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        state, "queued",
        "leaving it at 'none' tells the app no illustration is coming while a job waits for one"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_job_key_carries_the_style_version(pool: PgPool) -> sqlx::Result<()> {
    let stage = stage(&pool).await?;
    let ticket = fresh();

    complete(&pool, &stage, &args(&stage, &ticket, "2026-08-21")).await;

    let key: String = sqlx::query_scalar("select dedupe_key from job where kind = 'illustration'")
        .fetch_one(&pool)
        .await?;
    assert_eq!(
        key,
        format!("{}:{}", ticket.item, wardrobe_db::STYLE_VERSION),
        "keying on the item alone would make a future style change unrenderable"
    );
    Ok(())
}

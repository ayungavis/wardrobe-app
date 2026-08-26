mod common;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use chrono::{Duration, NaiveDate};
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

use common::{body_json, call, get_with_auth, session};

const DAY: &str = "2026-08-27";
const ITEM_NAME: &str = "Ayung's favourite blue shirt";
const ITEM_NOTE: &str = "bought in Bandung with mum";

fn day() -> NaiveDate {
    DAY.parse().expect("a real date")
}

async fn with_device(pool: &PgPool) -> sqlx::Result<(String, Uuid, Uuid)> {
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

async fn fetch(pool: &PgPool, token: &str, query: &str) -> Value {
    let response = call(
        pool.clone(),
        get_with_auth(
            &format!("/v1/challenges/deck{query}"),
            &format!("Bearer {token}"),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    body_json(response).await
}

fn sync(token: &str, name: &str, args: &Value) -> Request<Body> {
    let body = json!({ "mutations": [{ "id": Uuid::now_v7(), "name": name, "args": args }] });
    Request::builder()
        .method("POST")
        .uri("/v1/sync")
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(body.to_string()))
        .expect("request")
}

async fn item(pool: &PgPool, account: Uuid, category: &str) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item
             (id, account_id, category, name, description, garment_type, color, change_seq)
         values ($1, $2, $3, $4, $5, 't-shirt', 'white', 1)",
    )
    .bind(id)
    .bind(account)
    .bind(category)
    .bind(ITEM_NAME)
    .bind(ITEM_NOTE)
    .execute(pool)
    .await?;
    Ok(id)
}

async fn generated_card(
    pool: &PgPool,
    account: Uuid,
    slot: i16,
    garments: Option<(Uuid, Uuid)>,
) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_card
             (id, account_id, source, title, prompt_text, locale, model, prompt_version,
              local_date, deck_index, top_item_id, bottom_item_id)
         values ($1, $2, 'generated', 'A title', 'A prompt', 'en', 'a/model', 'v1', $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(account)
    .bind(day())
    .bind(slot)
    .bind(garments.map(|(top, _)| top))
    .bind(garments.map(|(_, bottom)| bottom))
    .execute(pool)
    .await?;
    Ok(id)
}

async fn full_deck(pool: &PgPool, account: Uuid) -> sqlx::Result<()> {
    for slot in 0..5_i16 {
        generated_card(pool, account, slot, None).await?;
    }
    Ok(())
}

// -------------------------------------------------------------------- reading

#[sqlx::test(migrations = "../../migrations")]
async fn a_day_without_a_generated_deck_falls_back_to_curated(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;

    let deck = fetch(&pool, &token, &format!("?localDate={DAY}")).await;

    assert_eq!(deck["source"], "curated");
    assert_eq!(
        deck["cards"].as_array().expect("cards").len(),
        5,
        "FR-080 says a daily-eligible user always receives a usable card, and a deck \
         that cannot be filled is not usable"
    );
    assert!(
        deck["cards"]
            .as_array()
            .expect("cards")
            .iter()
            .all(|card| card["topItemId"].is_null()),
        "curated cards are text-first (FR-008); they cannot reference a garment"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_generated_deck_wins_over_the_curated_catalog(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    full_deck(&pool, account).await?;

    let deck = fetch(&pool, &token, &format!("?localDate={DAY}")).await;

    assert_eq!(deck["source"], "generated");
    assert_eq!(deck["cards"][0]["prompt"], "A prompt");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_days_deck_is_never_returned(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    full_deck(&pool, account).await?;

    let deck = fetch(&pool, &token, "?localDate=2026-08-28").await;

    assert_eq!(
        deck["source"], "curated",
        "the deck is keyed to the device's local day, not to whatever exists"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn another_accounts_deck_is_never_returned(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;
    let (_, stranger) = session(&pool, Duration::days(1), false).await?;
    full_deck(&pool, stranger).await?;

    let deck = fetch(&pool, &token, &format!("?localDate={DAY}")).await;

    assert_eq!(deck["source"], "curated");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_card_whose_garment_was_deleted_reports_no_garments(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let top = item(&pool, account, "top").await?;
    let bottom = item(&pool, account, "bottom").await?;
    generated_card(&pool, account, 0, Some((top, bottom))).await?;
    sqlx::query("update wardrobe_item set deleted_at = now() where id = $1")
        .bind(top)
        .execute(&pool)
        .await?;

    let deck = fetch(&pool, &token, &format!("?localDate={DAY}")).await;

    assert_eq!(deck["source"], "generated");
    assert!(
        deck["cards"][0]["topItemId"].is_null() && deck["cards"][0]["bottomItemId"].is_null(),
        "the sentence names both garments, so half a pair is text-only, not half a picture"
    );
    assert_eq!(deck["cards"][0]["prompt"], "A prompt");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn no_deck_field_names_a_garment(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let top = item(&pool, account, "top").await?;
    let bottom = item(&pool, account, "bottom").await?;
    generated_card(&pool, account, 0, Some((top, bottom))).await?;

    let deck = fetch(&pool, &token, &format!("?localDate={DAY}"))
        .await
        .to_string();

    assert!(
        !deck.contains(ITEM_NAME) && !deck.contains(ITEM_NOTE),
        "the client already holds its own wardrobe; the deck ships ids, never item text"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_deck_without_a_day_is_refused(pool: PgPool) -> sqlx::Result<()> {
    let (token, _) = session(&pool, Duration::days(1), false).await?;

    let response = call(
        pool.clone(),
        get_with_auth("/v1/challenges/deck", &format!("Bearer {token}")),
    )
    .await;

    assert_eq!(
        response.status(),
        StatusCode::BAD_REQUEST,
        "the server must never guess which local day the caller means"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_deck_without_a_token_is_unauthenticated(pool: PgPool) {
    let response = call(
        pool.clone(),
        common::get(&format!("/v1/challenges/deck?localDate={DAY}")),
    )
    .await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ------------------------------------------------------------------- context

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_reports_its_zone_and_tomorrows_weather(pool: PgPool) -> sqlx::Result<()> {
    let (token, _, device) = with_device(&pool).await?;

    let response = call(
        pool.clone(),
        sync(
            &token,
            "upsertChallengeContext",
            &json!({
                "timeZone": "Asia/Jakarta",
                "locale": "id-ID",
                "weather": { "localDate": DAY, "condition": "rain", "highC": 31, "lowC": 24 }
            }),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);

    let stored: (
        Option<String>,
        Option<NaiveDate>,
        Option<String>,
        Option<i16>,
    ) = sqlx::query_as(
        "select time_zone, weather_local_date, weather_condition, weather_high_c
           from account_device where anonymous_id = $1",
    )
    .bind(device)
    .fetch_one(&pool)
    .await?;
    assert_eq!(stored.0.as_deref(), Some("Asia/Jakarta"));
    assert_eq!(stored.1, Some(day()));
    assert_eq!(stored.2.as_deref(), Some("rain"));
    assert_eq!(stored.3, Some(31));
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_unknown_time_zone_is_refused(pool: PgPool) -> sqlx::Result<()> {
    let (token, _, device) = with_device(&pool).await?;

    let response = call(
        pool.clone(),
        sync(
            &token,
            "upsertChallengeContext",
            &json!({ "timeZone": "Mars/Olympus" }),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    assert_eq!(body["results"][0]["status"], "failed");

    let stored: (Option<String>,) =
        sqlx::query_as("select time_zone from account_device where anonymous_id = $1")
            .bind(device)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        stored.0, None,
        "one unusable zone stored here raises 22023 for every account's enqueue, not just its own"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_free_text_weather_condition_is_refused(pool: PgPool) -> sqlx::Result<()> {
    let (token, _, device) = with_device(&pool).await?;

    let response = call(
        pool.clone(),
        sync(
            &token,
            "upsertChallengeContext",
            &json!({
                "timeZone": "Asia/Jakarta",
                "weather": {
                    "localDate": DAY,
                    "condition": "partly cloudy with a chance of my ex",
                    "highC": 31, "lowC": 24
                }
            }),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(body_json(response).await["results"][0]["status"], "failed");

    let stored: (Option<String>,) =
        sqlx::query_as("select weather_condition from account_device where anonymous_id = $1")
            .bind(device)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        stored.0, None,
        "the vocabulary is closed: free text from a device is free text in a prompt"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_cannot_write_context_onto_another_account(pool: PgPool) -> sqlx::Result<()> {
    let (token, account, _) = with_device(&pool).await?;
    let (_, _, stranger_device) = with_device(&pool).await?;
    sqlx::query("update session set device_id = $2 where account_id = $1")
        .bind(account)
        .bind(stranger_device)
        .execute(&pool)
        .await?;

    let response = call(
        pool.clone(),
        sync(
            &token,
            "upsertChallengeContext",
            &json!({ "timeZone": "Asia/Jakarta" }),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(body_json(response).await["results"][0]["status"], "failed");

    let stored: (Option<String>,) =
        sqlx::query_as("select time_zone from account_device where anonymous_id = $1")
            .bind(stranger_device)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        stored.0, None,
        "a session naming a device it does not own must not write that device's context"
    );
    Ok(())
}

// ------------------------------------------------------------- manual trigger

#[sqlx::test(migrations = "../../migrations")]
async fn the_manual_trigger_resets_a_failed_deck_job(pool: PgPool) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, status, attempts, last_error_code)
         values ($1, $2, $3, $4, 'failed', 3, 'provider_unavailable')",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(wardrobe_db::CHALLENGE_DECK)
    .bind(format!("{account}:{DAY}"))
    .execute(&pool)
    .await?;

    let response = call(
        pool.clone(),
        sync(
            &token,
            "generateChallengeDeck",
            &json!({ "localDate": DAY }),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);

    let job: (String, i32, Option<String>) = sqlx::query_as(
        "select status, attempts, last_error_code from job where kind = $1 and dedupe_key = $2",
    )
    .bind(wardrobe_db::CHALLENGE_DECK)
    .bind(format!("{account}:{DAY}"))
    .fetch_one(&pool)
    .await?;
    assert_eq!(
        (job.0.as_str(), job.1, job.2),
        ("pending", 0, None),
        "a deck that failed must be re-drivable, or the trigger cannot be used to test one"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn regenerating_keeps_a_card_an_active_challenge_still_cites(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (token, account) = session(&pool, Duration::days(1), false).await?;
    let accepted = generated_card(&pool, account, 0, None).await?;
    generated_card(&pool, account, 1, None).await?;
    sqlx::query(
        "insert into active_challenge
             (id, account_id, card_id, accepted_at, local_date, time_zone, change_seq)
         values ($1, $2, $3, now(), $4, 'Asia/Jakarta', 1)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(accepted)
    .bind(day())
    .execute(&pool)
    .await?;

    let response = call(
        pool.clone(),
        sync(
            &token,
            "generateChallengeDeck",
            &json!({ "localDate": DAY }),
        ),
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);

    let survivors: Vec<(Uuid,)> = sqlx::query_as(
        "select id from challenge_card where account_id = $1 and source = 'generated'",
    )
    .bind(account)
    .fetch_all(&pool)
    .await?;
    assert_eq!(
        survivors,
        vec![(accepted,)],
        "FR-006 forbids the server silently replacing an accepted daily state, and the \
         card_id foreign key would abort the whole batch anyway"
    );
    Ok(())
}

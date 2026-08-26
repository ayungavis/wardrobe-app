use chrono::NaiveDate;
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_worker::challenge;
use wardrobe_worker::inference::Provider;
use wardrobe_worker::{Outcome, run_one};
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

const DAY: &str = "2026-08-27";
const ITEM_NAME: &str = "Ayung's favourite blue shirt";
const ITEM_NOTE: &str = "bought in Bandung with mum, second-hand";

fn day() -> NaiveDate {
    DAY.parse().expect("a real date")
}

fn provider(server: &MockServer) -> Provider {
    Provider {
        client: reqwest::Client::new(),
        base_url: server.uri(),
        api_key: "test-key".to_owned(),
    }
}

fn five_cards() -> Value {
    let cards: Vec<Value> = (0..5)
        .map(|slot| json!({ "title": format!("Card {slot}"), "sentence": "Wear it today." }))
        .collect();
    reply(&json!({ "cards": cards }).to_string())
}

fn reply(content: &str) -> Value {
    json!({
        "provider": "a-provider",
        "usage": { "prompt_tokens": 11, "completion_tokens": 22 },
        "choices": [{ "message": { "role": "assistant", "content": content } }]
    })
}

async fn answer(server: &MockServer, template: ResponseTemplate) {
    Mock::given(method("POST"))
        .and(path("/chat/completions"))
        .respond_with(template)
        .mount(server)
        .await;
}

async fn sent_body(server: &MockServer) -> Value {
    let requests = server.received_requests().await.expect("recording");
    serde_json::from_slice(&requests.first().expect("one request").body).expect("json body")
}

async fn configure(pool: &PgPool, alternate: Option<&str>) -> sqlx::Result<()> {
    sqlx::query(
        "insert into ai_provider_allowlist (provider_slug, forbids_training, retention_policy, approved_by)
         values ('a-provider', true, 'zero', 'the test')",
    )
    .execute(pool)
    .await?;
    sqlx::query(
        "update ai_model_config
            set active_model = 'primary/model', alternate_model = $1, prompt_version = 'p1'
          where capability = 'challenge_text'",
    )
    .bind(alternate)
    .execute(pool)
    .await?;
    Ok(())
}

struct Scene {
    account: Uuid,
    job: Uuid,
}

async fn account(pool: &PgPool) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(id)
}

struct Wearable<'a> {
    category: &'a str,
    garment_type: &'a str,
    color: &'a str,
    worn_days_ago: Option<i64>,
}

async fn item(pool: &PgPool, account: Uuid, wearable: &Wearable<'_>) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item
             (id, account_id, category, name, description, garment_type, color, change_seq)
         values ($1, $2, $3, $4, $5, $6, $7, 1)",
    )
    .bind(id)
    .bind(account)
    .bind(wearable.category)
    .bind(ITEM_NAME)
    .bind(ITEM_NOTE)
    .bind(wearable.garment_type)
    .bind(wearable.color)
    .execute(pool)
    .await?;

    if let Some(days) = wearable.worn_days_ago {
        sqlx::query(
            "insert into wear_record (id, account_id, item_id, worn_on, change_seq)
             values ($1, $2, $3, $4::date - $5::int, 1)",
        )
        .bind(Uuid::now_v7())
        .bind(account)
        .bind(id)
        .bind(day())
        .bind(i32::try_from(days).unwrap_or(0))
        .execute(pool)
        .await?;
    }
    Ok(id)
}

async fn enqueue(pool: &PgPool, account: Uuid) -> sqlx::Result<Uuid> {
    let job = Uuid::now_v7();
    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload)
         values ($1, $2, $3, $4, jsonb_build_object('localDate', $5::text, 'accountId', $2::text))",
    )
    .bind(job)
    .bind(account)
    .bind(wardrobe_db::CHALLENGE_DECK)
    .bind(format!("{account}:{DAY}"))
    .bind(DAY)
    .execute(pool)
    .await?;
    Ok(job)
}

async fn scene(pool: &PgPool) -> sqlx::Result<Scene> {
    let account = account(pool).await?;
    let job = enqueue(pool, account).await?;
    Ok(Scene { account, job })
}

async fn dressed_scene(pool: &PgPool) -> sqlx::Result<Scene> {
    let account = account(pool).await?;
    for (category, garment_type, color, worn) in [
        ("top", "t-shirt", "white", Some(40)),
        ("top", "hoodie", "black", Some(12)),
        ("top", "blouse", "pink", None),
        ("bottom", "jeans", "blue", Some(30)),
        ("bottom", "skirt", "brown", Some(5)),
        ("bottom", "trousers", "beige", None),
    ] {
        item(
            pool,
            account,
            &Wearable {
                category,
                garment_type,
                color,
                worn_days_ago: worn,
            },
        )
        .await?;
    }
    let job = enqueue(pool, account).await?;
    Ok(Scene { account, job })
}

async fn run(pool: &PgPool, server: &MockServer, final_attempt: bool) -> Outcome {
    let provider = provider(server);
    let claimed = run_one(pool, wardrobe_db::CHALLENGE_DECK, |job| async move {
        challenge::generate_for(pool, &provider, &job, final_attempt).await
    })
    .await
    .expect("the claim itself works");
    claimed.expect("a job was waiting")
}

async fn deck(pool: &PgPool, account: Uuid) -> Vec<(i16, String, Option<Uuid>, Option<Uuid>)> {
    sqlx::query_as(
        "select deck_index, prompt_text, top_item_id, bottom_item_id
           from challenge_card
          where account_id = $1 and source = 'generated'
          order by deck_index",
    )
    .bind(account)
    .fetch_all(pool)
    .await
    .expect("deck rows")
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

// ------------------------------------------------------------- happy paths

#[sqlx::test(migrations = "../../migrations")]
async fn a_wardrobe_of_pairs_produces_five_cards_that_name_their_garments(
    pool: PgPool,
) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = dressed_scene(&pool).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    let cards = deck(&pool, scene.account).await;
    assert_eq!(cards.len(), challenge::DECK_SIZE);
    assert!(
        cards
            .iter()
            .all(|(_, _, top, bottom)| top.is_some() && bottom.is_some()),
        "three tops and three bottoms make five distinct pairs without running out"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_empty_wardrobe_still_produces_five_cards(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    let cards = deck(&pool, scene.account).await;
    assert_eq!(
        cards.len(),
        challenge::DECK_SIZE,
        "no wardrobe is the pairs=0 case of one code path, not a second one"
    );
    assert!(
        cards
            .iter()
            .all(|(_, _, top, bottom)| top.is_none() && bottom.is_none()),
        "a card cannot name a garment the wearer does not own"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_wardrobe_with_no_bottoms_still_produces_five_cards(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let account = account(&pool).await?;
    item(
        &pool,
        account,
        &Wearable {
            category: "top",
            garment_type: "t-shirt",
            color: "white",
            worn_days_ago: Some(40),
        },
    )
    .await?;
    enqueue(&pool, account).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);
    assert_eq!(deck(&pool, account).await.len(), challenge::DECK_SIZE);
    Ok(())
}

// --------------------------------------------------------------- selection

#[sqlx::test(migrations = "../../migrations")]
async fn the_five_cards_do_not_all_reuse_one_garment(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = dressed_scene(&pool).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;
    run(&pool, &server, true).await;

    let cards = deck(&pool, scene.account).await;
    let mut tops: Vec<Uuid> = cards.iter().filter_map(|(_, _, top, _)| *top).collect();
    tops.sort_unstable();
    tops.dedup();
    let mut bottoms: Vec<Uuid> = cards.iter().filter_map(|(_, _, _, bot)| *bot).collect();
    bottoms.sort_unstable();
    bottoms.dedup();

    assert!(
        tops.len() >= 3 && bottoms.len() >= 3,
        "without a reuse penalty the single most neglected garment wins every slot and \
         the deck stops being five challenges: {} tops, {} bottoms",
        tops.len(),
        bottoms.len()
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_least_recently_worn_pair_leads_the_deck(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let account = account(&pool).await?;
    let mut ids = Vec::new();
    for (category, garment_type, worn) in [
        ("top", "t-shirt", Some(2)),
        ("top", "t-shirt", Some(90)),
        ("bottom", "jeans", Some(2)),
        ("bottom", "jeans", Some(90)),
    ] {
        ids.push(
            item(
                &pool,
                account,
                &Wearable {
                    category,
                    garment_type,
                    color: "white",
                    worn_days_ago: worn,
                },
            )
            .await?,
        );
    }
    enqueue(&pool, account).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;
    run(&pool, &server, true).await;

    let cards = deck(&pool, account).await;
    let (_, _, top, bottom) = cards.first().expect("a first card");
    assert_eq!(
        (*top, *bottom),
        (Some(ids[1]), Some(ids[3])),
        "the pair nobody has worn for three months leads; everything else is equal here"
    );
    Ok(())
}

// ------------------------------------------------------------- FR-080 guard

#[sqlx::test(migrations = "../../migrations")]
async fn the_prompt_never_carries_a_name_a_description_or_an_id(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = dressed_scene(&pool).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;
    run(&pool, &server, true).await;

    let sent = sent_body(&server).await.to_string();
    assert!(
        !sent.contains(ITEM_NAME),
        "FR-080 allows derived, non-identifying context only, and a name a user typed is neither"
    );
    assert!(!sent.contains(ITEM_NOTE), "nor is a description");
    assert!(
        !sent.contains(&scene.account.to_string()),
        "and an account id identifies exactly one person"
    );
    assert!(
        sent.contains("t-shirt") && sent.contains("white"),
        "the derived attributes are what the model is given to write from"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_colour_a_user_typed_is_scrubbed_before_it_leaves(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let account = account(&pool).await?;
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, garment_type, color, change_seq)
         values ($1, $2, 'top', 't-shirt', 'blue (mum got it at the Bandung market)', 1)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .execute(&pool)
    .await?;
    item(
        &pool,
        account,
        &Wearable {
            category: "bottom",
            garment_type: "jeans",
            color: "black",
            worn_days_ago: Some(9),
        },
    )
    .await?;
    enqueue(&pool, account).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;
    run(&pool, &server, true).await;

    let sent = sent_body(&server).await.to_string();
    assert!(
        sent.contains("blue"),
        "the colour itself is derived context"
    );
    assert!(
        !sent.contains("Bandung") && !sent.contains("mum"),
        "colour is free text in the schema, so whatever a user typed there is scrubbed"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_request_asks_for_a_zero_retention_route(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    scene(&pool).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;
    run(&pool, &server, true).await;

    assert_eq!(
        sent_body(&server).await["provider"]["zdr"],
        json!(true),
        "FR-082 routes only through providers that will not train on what we send"
    );
    Ok(())
}

// -------------------------------------------------------------- validation

#[sqlx::test(migrations = "../../migrations")]
async fn a_reply_with_four_cards_is_rejected_and_writes_nothing(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool).await?;
    let server = MockServer::start().await;
    let four = json!({ "cards": (0..4)
        .map(|slot| json!({ "title": format!("Card {slot}"), "sentence": "Wear it." }))
        .collect::<Vec<Value>>() });
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(reply(&four.to_string())),
    )
    .await;

    run(&pool, &server, true).await;

    assert!(deck(&pool, scene.account).await.is_empty());
    assert_eq!(
        attempts(&pool, scene.job).await.first().expect("a row").2,
        "invalid_output",
        "a short deck is the model failing the schema, not the database failing us"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_over_long_sentence_never_reaches_the_table(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool).await?;
    let server = MockServer::start().await;
    let long = json!({ "cards": (0..5)
        .map(|_| json!({ "title": "Card", "sentence": "x".repeat(600) }))
        .collect::<Vec<Value>>() });
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(reply(&long.to_string())),
    )
    .await;

    run(&pool, &server, true).await;

    assert!(deck(&pool, scene.account).await.is_empty());
    assert_eq!(
        attempts(&pool, scene.job).await.first().expect("a row").2,
        "invalid_output",
        "checked in Rust as invalid output, not left to abort the transaction as a database error"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_provider_failure_leaves_no_partial_deck(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = dressed_scene(&pool).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(500)).await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Retrying);
    assert!(
        deck(&pool, scene.account).await.is_empty(),
        "the provider is called before the transaction opens, so a failure writes nothing"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_rate_limited_provider_moves_to_the_alternate(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, Some("alternate/model")).await?;
    let scene = scene(&pool).await?;
    let server = MockServer::start().await;
    answer(&server, ResponseTemplate::new(429)).await;

    assert_eq!(run(&pool, &server, false).await, Outcome::Retrying);
    sqlx::query("update job set status = 'pending', run_after = now() where id = $1")
        .bind(scene.job)
        .execute(&pool)
        .await?;
    run(&pool, &server, true).await;

    let rows = attempts(&pool, scene.job).await;
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[1].1, "alternate/model");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_account_over_budget_never_calls_the_provider(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = scene(&pool).await?;
    for attempt in 0..10 {
        sqlx::query(
            "insert into ai_inference_attempt
                 (id, account_id, capability, attempt_no, model, prompt_version, status)
             values ($1, $2, 'challenge_text', $3, 'primary/model', 'p1', 'succeeded')",
        )
        .bind(Uuid::now_v7())
        .bind(scene.account)
        .bind(attempt + 1)
        .execute(&pool)
        .await?;
    }
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);
    assert!(
        server
            .received_requests()
            .await
            .expect("recording")
            .is_empty(),
        "FR-076 checks the limit before the provider call, not after paying for it"
    );
    assert!(deck(&pool, scene.account).await.is_empty());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_second_run_never_writes_a_second_deck(pool: PgPool) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let scene = dressed_scene(&pool).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;
    run(&pool, &server, true).await;

    sqlx::query("update job set status = 'pending', run_after = now() where id = $1")
        .bind(scene.job)
        .execute(&pool)
        .await?;
    run(&pool, &server, true).await;

    assert_eq!(
        deck(&pool, scene.account).await.len(),
        challenge::DECK_SIZE,
        "a retried generation lands on the same slots instead of doubling the deck"
    );
    Ok(())
}

async fn worn_together(
    pool: &PgPool,
    account: Uuid,
    items: &[Uuid],
    days_ago: i64,
) -> sqlx::Result<()> {
    let completion = Uuid::now_v7();
    let card: (Uuid,) =
        sqlx::query_as("select id from challenge_card where source = 'curated' limit 1")
            .fetch_one(pool)
            .await?;
    sqlx::query(
        "insert into challenge_completion
             (id, account_id, card_id, local_date, time_zone, completed_at, status, change_seq)
         values ($1, $2, $3, $4::date - $5::int, 'Asia/Jakarta', now(), 'canonical', 1)",
    )
    .bind(completion)
    .bind(account)
    .bind(card.0)
    .bind(day())
    .bind(i32::try_from(days_ago).unwrap_or(0))
    .execute(pool)
    .await?;

    for item in items {
        sqlx::query(
            "insert into wear_record (id, account_id, item_id, completion_id, worn_on, change_seq)
             values ($1, $2, $3, $4, $5::date - $6::int, 1)",
        )
        .bind(Uuid::now_v7())
        .bind(account)
        .bind(item)
        .bind(completion)
        .bind(day())
        .bind(i32::try_from(days_ago).unwrap_or(0))
        .execute(pool)
        .await?;
    }
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_pair_already_worn_together_yields_to_one_that_never_was(
    pool: PgPool,
) -> sqlx::Result<()> {
    configure(&pool, None).await?;
    let account = account(&pool).await?;
    let mut ids = Vec::new();
    for (category, garment_type) in [
        ("top", "t-shirt"),
        ("top", "t-shirt"),
        ("bottom", "jeans"),
        ("bottom", "jeans"),
    ] {
        ids.push(
            item(
                &pool,
                account,
                &Wearable {
                    category,
                    garment_type,
                    color: "white",
                    worn_days_ago: None,
                },
            )
            .await?,
        );
    }
    worn_together(&pool, account, &[ids[0], ids[2]], 3).await?;
    enqueue(&pool, account).await?;
    let server = MockServer::start().await;
    answer(
        &server,
        ResponseTemplate::new(200).set_body_json(five_cards()),
    )
    .await;

    assert_eq!(run(&pool, &server, true).await, Outcome::Succeeded);

    let cards = deck(&pool, account).await;
    let (_, _, top, bottom) = cards.first().expect("a first card");
    assert!(
        !(*top == Some(ids[0]) && *bottom == Some(ids[2])),
        "the outfit they already wore together three days ago cannot lead a mix-and-match deck"
    );
    Ok(())
}

// ----------------------------------------------------------------- enqueue

async fn device(
    pool: &PgPool,
    account: Uuid,
    time_zone: &str,
    forecast_for: Option<NaiveDate>,
    last_seen_days_ago: i64,
) -> sqlx::Result<()> {
    sqlx::query(
        "insert into account_device
             (anonymous_id, account_id, last_seen_at, time_zone, locale,
              weather_local_date, weather_condition, weather_high_c, weather_low_c)
         values ($1, $2, now() - make_interval(days => $3::int), $4, 'id-ID', $5,
                 case when $5::date is null then null else 'rain' end,
                 case when $5::date is null then null else 31 end,
                 case when $5::date is null then null else 24 end)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(i32::try_from(last_seen_days_ago).unwrap_or(0))
    .bind(time_zone)
    .bind(forecast_for)
    .execute(pool)
    .await?;
    Ok(())
}

async fn queued(pool: &PgPool) -> Vec<(Uuid, String)> {
    sqlx::query_as("select id, dedupe_key from job where kind = $1 order by dedupe_key")
        .bind(wardrobe_db::CHALLENGE_DECK)
        .fetch_all(pool)
        .await
        .expect("job rows")
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_that_reported_tomorrows_weather_gets_a_job(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    let tomorrow = (chrono::Utc::now() + chrono::Duration::days(1)).date_naive();
    device(&pool, account, "Asia/Jakarta", Some(tomorrow), 0).await?;

    assert_eq!(challenge::enqueue_decks(&pool).await?, 1);
    assert_eq!(queued(&pool).await.len(), 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn running_the_enqueue_twice_queues_one_job(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    let tomorrow = (chrono::Utc::now() + chrono::Duration::days(1)).date_naive();
    device(&pool, account, "Asia/Jakarta", Some(tomorrow), 0).await?;

    challenge::enqueue_decks(&pool).await?;
    assert_eq!(challenge::enqueue_decks(&pool).await?, 0);
    assert_eq!(queued(&pool).await.len(), 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_last_seen_a_month_ago_is_dormant(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    let tomorrow = (chrono::Utc::now() + chrono::Duration::days(1)).date_naive();
    device(&pool, account, "Asia/Jakarta", Some(tomorrow), 45).await?;

    assert_eq!(challenge::enqueue_decks(&pool).await?, 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_device_without_any_weather_still_gets_a_deck(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    device(&pool, account, "Asia/Jakarta", None, 0).await?;

    assert_eq!(
        challenge::enqueue_decks(&pool).await?,
        1,
        "declining location costs the weather, not the deck; keying the enqueue on the \
         forecast left every such account on curated cards forever"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_deck_is_queued_for_the_devices_own_local_day(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    device(&pool, account, "Pacific/Kiritimati", None, 0).await?;

    challenge::enqueue_decks(&pool).await?;

    let (key,): (String,) =
        sqlx::query_as("select dedupe_key from job where kind = $1 and account_id = $2")
            .bind(wardrobe_db::CHALLENGE_DECK)
            .bind(account)
            .fetch_one(&pool)
            .await?;
    let expected: (chrono::NaiveDate,) =
        sqlx::query_as("select (now() at time zone 'Pacific/Kiritimati')::date")
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        key,
        format!("{account}:{}", expected.0),
        "UTC+14 is already tomorrow; the server reads the zone the device reported \
         rather than its own clock"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn one_unusable_time_zone_does_not_starve_every_other_account(
    pool: PgPool,
) -> sqlx::Result<()> {
    let tomorrow = (chrono::Utc::now() + chrono::Duration::days(1)).date_naive();
    let broken = account(&pool).await?;
    device(&pool, broken, "Mars/Olympus", Some(tomorrow), 0).await?;
    let healthy = account(&pool).await?;
    device(&pool, healthy, "Asia/Jakarta", Some(tomorrow), 0).await?;

    assert_eq!(
        challenge::enqueue_decks(&pool).await?,
        1,
        "one unusable zone raises 22023 for the whole statement, so it is filtered out \
         rather than allowed to cost every other account its deck"
    );
    Ok(())
}

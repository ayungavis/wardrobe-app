use rust_decimal::Decimal;
use sqlx::PgPool;
use uuid::{Uuid, uuid};

const FREESTYLE: Uuid = uuid!("019205f0-0000-7000-8000-000000000001");
const DECK_SIZE: usize = 5;

#[sqlx::test(migrations = "../../migrations")]
async fn the_curated_fallback_can_fill_a_whole_deck(pool: PgPool) -> sqlx::Result<()> {
    let usable: Vec<(Uuid,)> = sqlx::query_as(
        "select id from challenge_card
          where source = 'curated' and retired_at is null and id <> $1",
    )
    .bind(FREESTYLE)
    .fetch_all(&pool)
    .await?;

    assert!(
        usable.len() >= DECK_SIZE,
        "FR-008 makes the curated catalog the permanent fallback, and a fallback that cannot \
         fill a whole deck is not one; freestyle is a second completion path (FR-065), not a \
         deck slot, so it does not count. Found {}",
        usable.len()
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn challenge_text_is_configured_and_budgeted(pool: PgPool) -> sqlx::Result<()> {
    let config: Option<(String, String, Option<String>, String, bool)> = sqlx::query_as(
        "select model_class, active_model, alternate_model, prompt_version, enabled
           from ai_model_config where capability = 'challenge_text'",
    )
    .fetch_optional(&pool)
    .await?;

    let (model_class, active, alternate, prompt_version, enabled) =
        config.expect("FR-080 needs the challenge_text capability configured to be buildable");

    assert_eq!(model_class, "text");
    assert!(enabled);
    assert!(!active.is_empty());
    assert!(!prompt_version.is_empty(), "FR-073 pins a prompt version");
    assert!(
        alternate.is_some_and(|alternate| alternate != active),
        "FR-075's fallback chain needs a distinct alternate model to escalate to"
    );

    let limit: Option<(i32, Option<i64>, Option<Decimal>, bool)> = sqlx::query_as(
        "select window_seconds, max_requests, max_cost_usd, enabled
           from ai_usage_limit where scope = 'account' and capability = 'challenge_text'",
    )
    .fetch_optional(&pool)
    .await?;

    let (window_seconds, max_requests, max_cost_usd, enabled) =
        limit.expect("FR-076 enforces a per-account limit before any provider call");

    assert!(enabled);
    assert!(window_seconds > 0);
    assert!(
        max_requests.is_some() || max_cost_usd.is_some(),
        "a limit row that caps neither requests nor cost caps nothing"
    );
    Ok(())
}

// ---------------------------------------------------------------- fixtures

async fn account(pool: &PgPool) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(id)
}

async fn item(pool: &PgPool, account_id: Uuid, category: &str) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq)
         values ($1, $2, $3, 1)",
    )
    .bind(id)
    .bind(account_id)
    .bind(category)
    .execute(pool)
    .await?;
    Ok(id)
}

fn insert_card() -> &'static str {
    "insert into challenge_card
         (id, account_id, source, title, prompt_text, locale, model, prompt_version,
          local_date, deck_index, top_item_id, bottom_item_id)
     values ($1, $2, 'generated', 'A title', $3, 'en', 'a-model', 'v1', $4, $5, $6, $7)"
}

// ------------------------------------------------------------------- tests

#[sqlx::test(migrations = "../../migrations")]
async fn a_deck_slot_cannot_be_filled_twice(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    let day = chrono::NaiveDate::from_ymd_opt(2026, 8, 27).expect("a real date");

    for prompt in ["first", "second"] {
        let written = sqlx::query(insert_card())
            .bind(Uuid::now_v7())
            .bind(account)
            .bind(prompt)
            .bind(day)
            .bind(0_i16)
            .bind(Option::<Uuid>::None)
            .bind(Option::<Uuid>::None)
            .execute(&pool)
            .await;

        if prompt == "second" {
            assert!(
                written.is_err(),
                "a retried generation must land on the same slots, not double the deck"
            );
        } else {
            written?;
        }
    }
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_generated_card_must_name_the_day_it_belongs_to(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;

    let dateless = sqlx::query(
        "insert into challenge_card
             (id, account_id, source, title, prompt_text, locale, model, prompt_version, deck_index)
         values ($1, $2, 'generated', 'A title', 'A prompt', 'en', 'a-model', 'v1', 0)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .execute(&pool)
    .await;

    assert!(
        dateless.is_err(),
        "a generated card without a day is unreachable by the deck endpoint"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn deleting_an_item_leaves_its_card_as_text(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    let top = item(&pool, account, "top").await?;
    let bottom = item(&pool, account, "bottom").await?;
    let card = Uuid::now_v7();
    let day = chrono::NaiveDate::from_ymd_opt(2026, 8, 27).expect("a real date");

    sqlx::query(insert_card())
        .bind(card)
        .bind(account)
        .bind("A prompt")
        .bind(day)
        .bind(0_i16)
        .bind(Some(top))
        .bind(Some(bottom))
        .execute(&pool)
        .await?;

    sqlx::query("delete from wardrobe_item where id = $1")
        .bind(top)
        .execute(&pool)
        .await?;

    let survivor: Option<(String, Option<Uuid>, Option<Uuid>)> = sqlx::query_as(
        "select prompt_text, top_item_id, bottom_item_id from challenge_card where id = $1",
    )
    .bind(card)
    .fetch_optional(&pool)
    .await?;

    let (prompt, top_after, bottom_after) =
        survivor.expect("a completion may already cite this card, so it must survive its garment");
    assert_eq!(prompt, "A prompt");
    assert_eq!(top_after, None, "the removed garment lets go of the card");
    assert_eq!(
        bottom_after,
        Some(bottom),
        "its partner stays: the table records what is left, and the deck endpoint is \
         what reads a half pair as text-only (FR-010)"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_half_written_deck_cannot_be_committed(pool: PgPool) -> sqlx::Result<()> {
    let account = account(&pool).await?;
    let day = chrono::NaiveDate::from_ymd_opt(2026, 8, 27).expect("a real date");
    let mut tx = pool.begin().await?;

    for slot in 0..4_i16 {
        sqlx::query(insert_card())
            .bind(Uuid::now_v7())
            .bind(account)
            .bind("A prompt")
            .bind(day)
            .bind(slot)
            .bind(Option::<Uuid>::None)
            .bind(Option::<Uuid>::None)
            .execute(&mut *tx)
            .await?;
    }

    let overlong = sqlx::query(insert_card())
        .bind(Uuid::now_v7())
        .bind(account)
        .bind("x".repeat(600))
        .bind(day)
        .bind(4_i16)
        .bind(Option::<Uuid>::None)
        .bind(Option::<Uuid>::None)
        .execute(&mut *tx)
        .await;

    assert!(overlong.is_err());
    drop(tx);

    let landed: (i64,) =
        sqlx::query_as("select count(*) from challenge_card where account_id = $1")
            .bind(account)
            .fetch_one(&pool)
            .await?;
    assert_eq!(
        landed.0, 0,
        "a deck is written in one transaction: four good cards and one bad one leave nothing"
    );
    Ok(())
}

pub mod scoring;

use chrono::NaiveDate;
use serde::Deserialize;
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_db::ClaimedJob;

use crate::inference::{self, Accounting};
use crate::openrouter::{self, Chat, Failure, Rejection};
use scoring::{Garment, Pairing, Wardrobe, Weather, Weights};

pub const CAPABILITY: &str = "challenge_text";
pub const DECK_SIZE: usize = 5;
const QUALITY_ATTEMPTS: i64 = 2;
const MAX_TITLE: usize = 60;
const MAX_SENTENCE: usize = 200;
// ponytail: 500 accounts a tick drains far past the pilot at a five-second poll.
// Raise it, or shard the scan by account_id range, when a tick stops emptying
// the backlog.
const ENQUEUE_BATCH: i64 = 500;
// ponytail: a device silent for a month gets no deck, and costs nothing. Tune it
// from retention data; it is the only dormancy signal that exists.
const DORMANT_AFTER_DAYS: i32 = 30;

const SYSTEM_PROMPT: &str = "You write daily outfit-challenge cards for a wardrobe app. Your voice \
     is Gen-Z, warm and playful, never cringe. No emoji, no hashtags, no brand names, no prices, no \
     shopping advice, no people. For each numbered slot write a title of at most 60 characters and \
     exactly one sentence of at most 200 characters. A slot that lists two garments dares the \
     wearer to combine those two today, naming them by type and colour only. A slot marked \"no \
     outfit\" is about what to wear given the weather and what is in style this month, and must \
     never pretend to know what the wearer owns. Only call a garment neglected when its unworn \
     count is genuinely large; never claim rarity otherwise. Reply with JSON only.";

/// # Errors
///
/// Returns any database error unchanged.
pub async fn ready(pool: &PgPool) -> sqlx::Result<bool> {
    inference::ready(pool, CAPABILITY).await
}

// ----------------------------------------------------------------- context

pub struct Context {
    pub local_date: NaiveDate,
    pub locale: String,
    pub condition: Option<String>,
    pub weather: Option<Weather>,
}

async fn context(
    pool: &PgPool,
    account: Uuid,
    local_date: NaiveDate,
) -> Result<Context, &'static str> {
    let row: Option<ContextRow> = sqlx::query_as(
        "select locale, weather_local_date, weather_condition, weather_high_c, weather_low_c
           from account_device
          where account_id = $1 and time_zone is not null
          order by last_seen_at desc nulls last
          limit 1",
    )
    .bind(account)
    .fetch_optional(pool)
    .await
    .map_err(|_| "database")?;

    let Some(ContextRow {
        locale,
        weather_local_date: forecast_for,
        weather_condition: condition,
        weather_high_c: high_c,
        weather_low_c: low_c,
    }) = row
    else {
        return Ok(Context {
            local_date,
            locale: "en".to_owned(),
            condition: None,
            weather: None,
        });
    };

    let fresh = forecast_for == Some(local_date);
    let weather = match (fresh, condition.as_deref(), high_c, low_c) {
        (true, Some(condition), Some(high_c), Some(low_c)) => Some(Weather {
            high_c,
            low_c,
            wet: matches!(condition, "rain" | "storm" | "snow"),
        }),
        _ => None,
    };

    Ok(Context {
        local_date,
        locale: locale.unwrap_or_else(|| "en".to_owned()),
        condition: fresh.then_some(condition).flatten(),
        weather,
    })
}

async fn wardrobe(
    pool: &PgPool,
    account: Uuid,
    local_date: NaiveDate,
) -> Result<Wardrobe, &'static str> {
    let garments: Vec<Garment> = sqlx::query_as::<_, GarmentRow>(
        "with worn as (
             select item_id, max(worn_on) as last_worn, count(*) as wear_count
               from wear_record
              where account_id = $1 and deleted_at is null
              group by item_id
         )
         select i.id, i.category, i.garment_type, i.color,
                ($2::date - w.last_worn) as days_since_worn,
                coalesce(w.wear_count, 0) as wear_count,
                (i.illustration_state = 'ready') as renderable
           from wardrobe_item i
           left join worn w on w.item_id = i.id
          where i.account_id = $1 and i.deleted_at is null
            and i.category in ('top', 'bottom')",
    )
    .bind(account)
    .bind(local_date)
    .fetch_all(pool)
    .await
    .map_err(|_| "database")?
    .into_iter()
    .map(GarmentRow::into_garment)
    .collect();

    let last_together: Vec<(Uuid, Uuid, i64)> = sqlx::query_as(
        "select a.item_id, b.item_id, min($2::date - a.worn_on)::bigint
           from wear_record a
           join wear_record b
             on a.completion_id = b.completion_id and a.item_id < b.item_id
          where a.account_id = $1 and a.deleted_at is null and b.deleted_at is null
          group by a.item_id, b.item_id",
    )
    .bind(account)
    .bind(local_date)
    .fetch_all(pool)
    .await
    .map_err(|_| "database")?;

    Ok(Wardrobe {
        garments,
        last_together,
    })
}

#[derive(sqlx::FromRow)]
struct ContextRow {
    locale: Option<String>,
    weather_local_date: Option<NaiveDate>,
    weather_condition: Option<String>,
    weather_high_c: Option<i16>,
    weather_low_c: Option<i16>,
}

#[derive(sqlx::FromRow)]
struct GarmentRow {
    id: Uuid,
    category: String,
    garment_type: Option<String>,
    color: Option<String>,
    days_since_worn: Option<i32>,
    wear_count: i64,
    renderable: bool,
}

impl GarmentRow {
    fn into_garment(self) -> Garment {
        Garment {
            id: self.id,
            category: self.category,
            garment_type: self.garment_type,
            color: self.color,
            days_since_worn: self.days_since_worn.map(i64::from),
            wear_count: self.wear_count,
            renderable: self.renderable,
        }
    }
}

// ------------------------------------------------------------------ prompt

fn weights(config: &inference::Config) -> Weights {
    let default = Weights::default();
    let weight = |key: &str, fallback: f64| {
        config
            .params
            .get("weights")
            .and_then(|weights| weights.get(key))
            .and_then(serde_json::Value::as_f64)
            .unwrap_or(fallback)
    };
    Weights {
        neglect: weight("neglect", default.neglect),
        rarity: weight("rarity", default.rarity),
        novelty: weight("novelty", default.novelty),
        weather: weight("weather", default.weather),
        colour: weight("colour", default.colour),
        renderable: weight("renderable", default.renderable),
        reuse: weight("reuse", default.reuse),
    }
}

fn describe_garment(garment: &Garment) -> String {
    let kind = scoring::safe_type(garment.garment_type.as_deref())
        .unwrap_or_else(|| garment.category.clone());
    let colour = scoring::safe_colour(garment.color.as_deref());
    let worn = match garment.days_since_worn {
        None => "never worn".to_owned(),
        Some(days) => format!("unworn {days} days"),
    };
    match colour {
        Some(colour) => format!("{kind}, {colour}, {worn}"),
        None => format!("{kind}, {worn}"),
    }
}

fn ask(context: &Context, wardrobe: &Wardrobe, pairs: &[Pairing]) -> String {
    let mut lines = Vec::with_capacity(DECK_SIZE + 2);
    lines.push(format!("Locale: {}.", context.locale));
    lines.push(format!("Date: {}.", context.local_date));
    match (context.condition.as_deref(), context.weather) {
        (Some(condition), Some(weather)) => lines.push(format!(
            "Weather that day: {condition}, high {}C, low {}C.",
            weather.high_c, weather.low_c
        )),
        _ => lines.push("Weather that day: unknown.".to_owned()),
    }

    let find = |id: Uuid| wardrobe.garments.iter().find(|garment| garment.id == id);
    for slot in 0..DECK_SIZE {
        let described = pairs.get(slot).and_then(|pair| {
            let top = find(pair.top)?;
            let bottom = find(pair.bottom)?;
            Some(format!(
                "{}. top: {}; bottom: {}",
                slot + 1,
                describe_garment(top),
                describe_garment(bottom)
            ))
        });
        lines.push(described.unwrap_or_else(|| format!("{}. no outfit", slot + 1)));
    }
    lines.join("\n")
}

fn schema() -> serde_json::Value {
    serde_json::json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["cards"],
        "properties": {
            "cards": {
                "type": "array",
                "minItems": DECK_SIZE,
                "maxItems": DECK_SIZE,
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["title", "sentence"],
                    "properties": {
                        "title": { "type": "string", "maxLength": MAX_TITLE },
                        "sentence": { "type": "string", "maxLength": MAX_SENTENCE }
                    }
                }
            }
        }
    })
}

#[derive(Deserialize)]
struct Reply {
    cards: Vec<Card>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Card {
    pub title: String,
    pub sentence: String,
}

fn parse_deck(content: &str) -> Result<Vec<Card>, Failure> {
    let reply: Reply = serde_json::from_str(content).map_err(|_| Failure::InvalidOutput)?;
    if reply.cards.len() != DECK_SIZE {
        return Err(Failure::InvalidOutput);
    }
    let cards: Vec<Card> = reply
        .cards
        .into_iter()
        .map(|card| Card {
            title: card.title.trim().to_owned(),
            sentence: card.sentence.trim().to_owned(),
        })
        .collect();
    let sound = cards.iter().all(|card| {
        !card.title.is_empty()
            && !card.sentence.is_empty()
            && card.title.chars().count() <= MAX_TITLE
            && card.sentence.chars().count() <= MAX_SENTENCE
    });
    sound.then_some(cards).ok_or(Failure::InvalidOutput)
}

// ------------------------------------------------------------------- write

async fn write_deck(
    pool: &PgPool,
    account: Uuid,
    context: &Context,
    pairs: &[Pairing],
    cards: &[Card],
    pinned: &inference::Pinned,
    prompt_version: &str,
) -> Result<(), &'static str> {
    let mut tx = pool.begin().await.map_err(|_| "database")?;
    for (slot, card) in cards.iter().enumerate() {
        let index = i16::try_from(slot).map_err(|_| "database")?;
        let pair = pairs.get(slot);
        sqlx::query(
            "insert into challenge_card
                 (id, account_id, source, title, prompt_text, locale, model, prompt_version,
                  local_date, deck_index, top_item_id, bottom_item_id)
             values ($1, $2, 'generated', $3, $4, $5, $6, $7, $8, $9, $10, $11)
             on conflict (account_id, local_date, deck_index) do nothing",
        )
        .bind(Uuid::now_v7())
        .bind(account)
        .bind(&card.title)
        .bind(&card.sentence)
        .bind(&context.locale)
        .bind(&pinned.model)
        .bind(prompt_version)
        .bind(context.local_date)
        .bind(index)
        .bind(pair.map(|pair| pair.top))
        .bind(pair.map(|pair| pair.bottom))
        .execute(&mut *tx)
        .await
        .map_err(|_| "database")?;
    }
    tx.commit().await.map_err(|_| "database")
}

async fn already_written(
    pool: &PgPool,
    account: Uuid,
    local_date: NaiveDate,
) -> Result<bool, &'static str> {
    let (exists,): (bool,) = sqlx::query_as(
        "select exists (
             select 1 from challenge_card
              where account_id = $1 and local_date = $2 and source = 'generated'
         )",
    )
    .bind(account)
    .bind(local_date)
    .fetch_one(pool)
    .await
    .map_err(|_| "database")?;
    Ok(exists)
}

// ----------------------------------------------------------------- enqueue

/// # Errors
///
/// Returns any database error unchanged.
pub async fn enqueue_decks(pool: &PgPool) -> sqlx::Result<u64> {
    let due: Vec<(Uuid, NaiveDate)> = sqlx::query_as(
        "select d.account_id, (now() at time zone d.time_zone)::date as local_date
           from (
               select distinct on (ad.account_id) ad.account_id, ad.time_zone
                 from account_device ad
                where ad.time_zone is not null
                  and ad.last_seen_at > now() - make_interval(days => $1::int)
                  -- Defence in depth: the mutation validates the zone, but one bad
                  -- row written any other way raises 22023 and starves every
                  -- account's deck, not just its own.
                  and ad.time_zone in (select name from pg_timezone_names)
                order by ad.account_id, ad.last_seen_at desc
           ) d
           join account a on a.id = d.account_id and a.deleted_at is null
          where not exists (
                select 1 from challenge_card c
                 where c.account_id = d.account_id
                   and c.local_date = (now() at time zone d.time_zone)::date
                   and c.source = 'generated'
            )
          order by d.account_id
          limit $2",
    )
    .bind(DORMANT_AFTER_DAYS)
    .bind(ENQUEUE_BATCH)
    .fetch_all(pool)
    .await?;

    if due.is_empty() {
        return Ok(0);
    }

    let ids: Vec<Uuid> = due.iter().map(|_| Uuid::now_v7()).collect();
    let accounts: Vec<Uuid> = due.iter().map(|(account, _)| *account).collect();
    let days: Vec<NaiveDate> = due.iter().map(|(_, day)| *day).collect();

    let queued = sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload)
         select u.id, u.account_id, $4,
                u.account_id::text || ':' || u.local_date::text,
                jsonb_build_object('localDate', u.local_date::text,
                                   'accountId', u.account_id::text)
           from unnest($1::uuid[], $2::uuid[], $3::date[]) as u(id, account_id, local_date)
         on conflict (kind, dedupe_key) do nothing",
    )
    .bind(&ids)
    .bind(&accounts)
    .bind(&days)
    .bind(wardrobe_db::CHALLENGE_DECK)
    .execute(pool)
    .await?;

    Ok(queued.rows_affected())
}

// -------------------------------------------------------------- the attempt

fn day_of(job: &ClaimedJob) -> Result<NaiveDate, &'static str> {
    job.payload
        .get("localDate")
        .and_then(serde_json::Value::as_str)
        .and_then(|day| day.parse().ok())
        .ok_or("bad_payload")
}

fn account_of(job: &ClaimedJob) -> Result<Uuid, &'static str> {
    job.payload
        .get("accountId")
        .and_then(serde_json::Value::as_str)
        .and_then(|account| account.parse().ok())
        .ok_or("bad_payload")
}

/// # Errors
///
/// Returns a classified code. A permanent failure writes no cards at all: the
/// deck endpoint's curated fallback covers the day, which is what FR-080 asks
/// for.
pub async fn generate_for(
    pool: &PgPool,
    provider: &inference::Provider,
    job: &ClaimedJob,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let local_date = day_of(job)?;
    let account = account_of(job)?;
    if already_written(pool, account, local_date).await? {
        return Ok(());
    }

    let config = inference::config(pool, CAPABILITY).await?;
    let context = context(pool, account, local_date).await?;
    let wardrobe = wardrobe(pool, account, local_date).await?;
    let pairs = scoring::choose(&wardrobe, context.weather, &weights(&config), DECK_SIZE);

    let pinned = inference::pin(
        pool,
        job.id,
        &config.active_model,
        config.alternate_model.as_deref(),
        QUALITY_ATTEMPTS,
    )
    .await?;

    if !inference::within_limits(pool, CAPABILITY, account).await? {
        return inference::record(
            pool,
            CAPABILITY,
            job,
            account,
            &pinned,
            &config.prompt_version,
            &Accounting {
                status: "skipped_limit",
                provider_route: None,
                latency_ms: None,
                input_tokens: None,
                output_tokens: None,
                http_status: None,
            },
        )
        .await;
    }

    let started = std::time::Instant::now();
    let outcome = openrouter::chat(
        &provider.client,
        &provider.base_url,
        &provider.api_key,
        &Chat {
            model: &pinned.model,
            system: SYSTEM_PROMPT,
            user: &ask(&context, &wardrobe, &pairs),
            schema: schema(),
            seed: pinned.seed,
        },
    )
    .await;
    let latency_ms = i32::try_from(started.elapsed().as_millis()).ok();

    settle(
        Settling {
            pool,
            job,
            account,
            context: &context,
            pairs: &pairs,
            pinned: &pinned,
            prompt_version: &config.prompt_version,
        },
        outcome,
        latency_ms,
        final_attempt,
    )
    .await
}

struct Settling<'a> {
    pool: &'a PgPool,
    job: &'a ClaimedJob,
    account: Uuid,
    context: &'a Context,
    pairs: &'a [Pairing],
    pinned: &'a inference::Pinned,
    prompt_version: &'a str,
}

async fn settle(
    work: Settling<'_>,
    outcome: Result<openrouter::Answered, Rejection>,
    latency_ms: Option<i32>,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let answered = match outcome {
        Ok(answered) => answered,
        Err(rejection) => {
            tracing::warn!(
                rejection = rejection.failure.status(),
                provider.status = rejection.http_status,
                "the provider declined to write the deck"
            );
            record(
                &work,
                rejection.failure.status(),
                None,
                latency_ms,
                None,
                rejection.http_status.map(i32::from),
            )
            .await?;
            return retry_or_settle(rejection.failure, work.pinned, final_attempt);
        }
    };

    let parsed = parse_deck(&answered.content);
    let route = answered.provider_route.clone();
    let tokens = (answered.input_tokens, answered.output_tokens);
    let status = if parsed.is_ok() {
        "succeeded"
    } else {
        "invalid_output"
    };
    record(&work, status, route, latency_ms, Some(tokens), None).await?;

    let Ok(cards) = parsed else {
        return retry_or_settle(Failure::InvalidOutput, work.pinned, final_attempt);
    };

    write_deck(
        work.pool,
        work.account,
        work.context,
        work.pairs,
        &cards,
        work.pinned,
        work.prompt_version,
    )
    .await
}

async fn record(
    work: &Settling<'_>,
    status: &str,
    provider_route: Option<String>,
    latency_ms: Option<i32>,
    tokens: Option<(Option<i64>, Option<i64>)>,
    http_status: Option<i32>,
) -> Result<(), &'static str> {
    let (input_tokens, output_tokens) = tokens.unwrap_or((None, None));
    inference::record(
        work.pool,
        CAPABILITY,
        work.job,
        work.account,
        work.pinned,
        work.prompt_version,
        &Accounting {
            status,
            provider_route,
            latency_ms,
            input_tokens,
            output_tokens,
            http_status,
        },
    )
    .await
}

fn retry_or_settle(
    failure: Failure,
    pinned: &inference::Pinned,
    final_attempt: bool,
) -> Result<(), &'static str> {
    let worth = match failure {
        Failure::Unavailable => true,
        Failure::Ineligible => false,
        Failure::Refused => pinned.another_model_available,
        Failure::InvalidOutput => pinned.another_model_available || pinned.quality_attempts_left,
    };
    if !final_attempt && worth {
        return Err("provider_retryable");
    }
    Ok(())
}

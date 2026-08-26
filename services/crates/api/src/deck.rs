use chrono::NaiveDate;
use serde::Serialize;
use sqlx::PgPool;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::Error;

pub const DECK_SIZE: i64 = 5;
const FREESTYLE: Uuid = uuid::uuid!("019205f0-0000-7000-8000-000000000001");

#[derive(Debug, Serialize, sqlx::FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct DeckCard {
    pub id: Uuid,
    pub title: Option<String>,
    pub prompt: String,
    pub top_item_id: Option<Uuid>,
    pub bottom_item_id: Option<Uuid>,
}

pub struct Deck {
    pub cards: Vec<DeckCard>,
    pub generated: bool,
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn for_day(
    pool: &PgPool,
    account_id: Uuid,
    local_date: NaiveDate,
    locale: &str,
) -> Result<Deck, Error> {
    let generated: Vec<DeckCard> = sqlx::query_as(
        "select c.id, c.title, c.prompt_text as prompt,
                case when t.id is not null and b.id is not null then t.id end as top_item_id,
                case when t.id is not null and b.id is not null then b.id end as bottom_item_id
           from challenge_card c
           left join wardrobe_item t on t.id = c.top_item_id and t.deleted_at is null
           left join wardrobe_item b on b.id = c.bottom_item_id and b.deleted_at is null
          where c.account_id = $1 and c.local_date = $2
            and c.source = 'generated' and c.retired_at is null
          order by c.deck_index",
    )
    .bind(account_id)
    .bind(local_date)
    .fetch_all(pool)
    .await?;

    if !generated.is_empty() {
        return Ok(Deck {
            cards: generated,
            generated: true,
        });
    }

    let curated: Vec<DeckCard> = sqlx::query_as(
        "select id, title, prompt_text as prompt,
                null::uuid as top_item_id, null::uuid as bottom_item_id
           from challenge_card
          where account_id is null and source = 'curated' and retired_at is null and id <> $1
          order by (locale = $2) desc, id
          limit $3",
    )
    .bind(FREESTYLE)
    .bind(locale)
    .bind(DECK_SIZE)
    .fetch_all(pool)
    .await?;

    Ok(Deck {
        cards: curated,
        generated: false,
    })
}

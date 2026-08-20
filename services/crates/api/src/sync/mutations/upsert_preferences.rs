use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;

const RECENT_STICKER_LIMIT: usize = 12;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    onboarding_completed_at: Option<DateTime<Utc>>,
    recent_sticker_ids: Option<Vec<String>>,
    last_text_style: Option<Value>,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Preferences {
    onboarding_completed_at: Option<DateTime<Utc>>,
    recent_sticker_ids: Vec<String>,
    last_text_style: Value,
    change_seq: i64,
}

impl Preferences {
    fn holds(&self, wanted: &Wanted) -> bool {
        self.onboarding_completed_at == wanted.onboarding_completed_at
            && self.recent_sticker_ids == wanted.recent_sticker_ids
            && self.last_text_style == wanted.last_text_style
    }
}

struct Wanted {
    onboarding_completed_at: Option<DateTime<Utc>>,
    recent_sticker_ids: Vec<String>,
    last_text_style: Value,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments, a sticker list past
/// [`RECENT_STICKER_LIMIT`], or a text style that is not a JSON object.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;

    let mut tx = pool.begin().await?;
    let current: Option<Preferences> = sqlx::query_as(
        "select onboarding_completed_at, recent_sticker_ids, last_text_style, change_seq
           from account_preference
          where account_id = $1
          for update",
    )
    .bind(account_id)
    .fetch_optional(&mut *tx)
    .await?;

    let wanted = Wanted {
        onboarding_completed_at: args
            .onboarding_completed_at
            .or_else(|| current.as_ref().and_then(|row| row.onboarding_completed_at)),
        recent_sticker_ids: args.recent_sticker_ids.unwrap_or_else(|| {
            current
                .as_ref()
                .map_or_else(Vec::new, |row| row.recent_sticker_ids.clone())
        }),
        last_text_style: args.last_text_style.unwrap_or_else(|| {
            current
                .as_ref()
                .map_or_else(|| json!({}), |row| row.last_text_style.clone())
        }),
    };

    if wanted.recent_sticker_ids.len() > RECENT_STICKER_LIMIT || !wanted.last_text_style.is_object()
    {
        return Err(Error::BadRequest);
    }

    if let Some(current) = current.as_ref().filter(|row| row.holds(&wanted)) {
        let unchanged = serde_json::to_value(current).map_err(|_| Error::BadRequest)?;
        tx.commit().await?;
        return Ok(unchanged);
    }

    let change_seq = wardrobe_db::next_change_seq(&mut tx, account_id).await?;
    let saved: Preferences = sqlx::query_as(
        "insert into account_preference
             (account_id, onboarding_completed_at, recent_sticker_ids, last_text_style, change_seq)
         values ($1, $2, $3, $4, $5)
         on conflict (account_id) do update
            set onboarding_completed_at = excluded.onboarding_completed_at,
                recent_sticker_ids      = excluded.recent_sticker_ids,
                last_text_style         = excluded.last_text_style,
                change_seq              = excluded.change_seq
         returning onboarding_completed_at, recent_sticker_ids, last_text_style, change_seq",
    )
    .bind(account_id)
    .bind(wanted.onboarding_completed_at)
    .bind(&wanted.recent_sticker_ids)
    .bind(&wanted.last_text_style)
    .bind(change_seq)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;

    serde_json::to_value(&saved).map_err(|_| Error::BadRequest)
}

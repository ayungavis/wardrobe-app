use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Serialize, Serializer};
use serde_json::Value;
use sqlx::PgPool;
use sqlx::postgres::PgRow;
use uuid::Uuid;

use crate::error::Error;

fn base64_bytes<S: Serializer>(bytes: &[u8], serializer: S) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(&STANDARD.encode(bytes))
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn fetch<T>(
    pool: &PgPool,
    sql: &str,
    account_id: Uuid,
    since: i64,
    limit: i64,
) -> Result<Vec<T>, Error>
where
    T: for<'r> sqlx::FromRow<'r, PgRow> + Send + Unpin,
{
    sqlx::query_as::<_, T>(sql)
        .bind(account_id)
        .bind(since)
        .bind(limit)
        .fetch_all(pool)
        .await
        .map_err(Error::from)
}

macro_rules! feed_query {
    ($table:literal, $columns:literal) => {
        concat!(
            "select ",
            $columns,
            " from ",
            $table,
            " where account_id = $1 and change_seq > $2 order by change_seq limit $3"
        )
    };
}

// --------------------------------------------------------------------- items

pub const WARDROBE_ITEM: &str = feed_query!(
    "wardrobe_item",
    "id, category, name, color, garment_type, description, attribute_revisions, \
     current_illustration_id, illustration_state, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct WardrobeItem {
    pub id: Uuid,
    pub category: String,
    pub name: Option<String>,
    pub color: Option<String>,
    pub garment_type: Option<String>,
    pub description: Option<String>,
    #[schema(value_type = Object)]
    pub attribute_revisions: Value,
    pub current_illustration_id: Option<Uuid>,
    pub illustration_state: String,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const ITEM_FINGERPRINT: &str = feed_query!(
    "item_fingerprint",
    "id, item_id, version, color_lab, aspect_ratio, feature_print, mask_quality, \
     source_photo_id, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ItemFingerprint {
    pub id: Uuid,
    pub item_id: Uuid,
    pub version: String,
    pub color_lab: Vec<f32>,
    pub aspect_ratio: f32,
    #[serde(serialize_with = "base64_bytes")]
    #[schema(value_type = String, format = Byte)]
    pub feature_print: Vec<u8>,
    pub mask_quality: f32,
    pub source_photo_id: Option<Uuid>,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const ITEM_CUTOUT: &str = feed_query!(
    "item_cutout",
    "id, item_id, media_object_id, source_photo_id, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ItemCutout {
    pub id: Uuid,
    pub item_id: Uuid,
    pub media_object_id: Uuid,
    pub source_photo_id: Option<Uuid>,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const ITEM_ILLUSTRATION: &str = feed_query!(
    "item_illustration",
    "id, item_id, media_object_id, style_version, model, prompt_version, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ItemIllustration {
    pub id: Uuid,
    pub item_id: Uuid,
    pub media_object_id: Uuid,
    pub style_version: String,
    pub model: String,
    pub prompt_version: String,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const WARDROBE_ITEM_CONFLICT: &str = feed_query!(
    "wardrobe_item_conflict",
    "id, item_id, field, value, revision, origin_device, change_seq, resolved_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct WardrobeItemConflict {
    pub id: Uuid,
    pub item_id: Uuid,
    pub field: String,
    pub value: Option<String>,
    pub revision: i64,
    pub origin_device: Option<Uuid>,
    pub change_seq: i64,
    /// This table resolves rather than deletes, so it carries no tombstone.
    pub resolved_at: Option<DateTime<Utc>>,
}

// -------------------------------------------------------------------- photos

pub const PHOTO: &str = feed_query!(
    "photo",
    "id, media_object_id, source, captured_at, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Photo {
    pub id: Uuid,
    pub media_object_id: Uuid,
    pub source: String,
    pub captured_at: Option<DateTime<Utc>>,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const PHOTO_DERIVATIVE: &str = feed_query!(
    "photo_derivative",
    "id, photo_id, media_object_id, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PhotoDerivative {
    pub id: Uuid,
    pub photo_id: Uuid,
    pub media_object_id: Uuid,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const CANVAS_DOCUMENT: &str = feed_query!(
    "canvas_document",
    "id, completion_id, derivative_id, schema_version, media_object_id, \
     history_media_object_id, history_step_count, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CanvasDocument {
    pub id: Uuid,
    pub completion_id: Uuid,
    pub derivative_id: Uuid,
    pub schema_version: i32,
    pub media_object_id: Uuid,
    pub history_media_object_id: Option<Uuid>,
    pub history_step_count: Option<i32>,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

// ----------------------------------------------------------------- the loop

pub const CHALLENGE_COMPLETION: &str = feed_query!(
    "challenge_completion",
    "id, card_id, local_date, time_zone, completed_at, status, photo_id, \
     current_derivative_id, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeCompletion {
    pub id: Uuid,
    pub card_id: Uuid,
    pub local_date: NaiveDate,
    pub time_zone: String,
    pub completed_at: DateTime<Utc>,
    pub status: String,
    pub photo_id: Option<Uuid>,
    pub current_derivative_id: Option<Uuid>,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const ACTIVE_CHALLENGE: &str = feed_query!(
    "active_challenge",
    "id, card_id, accepted_at, local_date, time_zone, photo_id, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ActiveChallenge {
    pub id: Uuid,
    pub card_id: Uuid,
    pub accepted_at: DateTime<Utc>,
    pub local_date: NaiveDate,
    pub time_zone: String,
    pub photo_id: Option<Uuid>,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

pub const WEAR_RECORD: &str = feed_query!(
    "wear_record",
    "id, item_id, completion_id, source_photo_id, worn_on, revision, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct WearRecord {
    pub id: Uuid,
    pub item_id: Uuid,
    pub completion_id: Option<Uuid>,
    pub source_photo_id: Option<Uuid>,
    pub worn_on: NaiveDate,
    pub revision: i32,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

// --------------------------------------------------------------- preferences

pub const ACCOUNT_PREFERENCE: &str = feed_query!(
    "account_preference",
    "onboarding_completed_at, recent_sticker_ids, last_text_style, change_seq, deleted_at"
);

#[derive(Debug, Serialize, sqlx::FromRow, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AccountPreference {
    pub onboarding_completed_at: Option<DateTime<Utc>>,
    pub recent_sticker_ids: Vec<String>,
    #[schema(value_type = Object)]
    pub last_text_style: Value,
    pub change_seq: i64,
    pub deleted_at: Option<DateTime<Utc>>,
}

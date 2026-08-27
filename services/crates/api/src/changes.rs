pub mod records;

use serde::Serialize;
use sqlx::PgPool;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::error::Error;

pub const DEFAULT_LIMIT: i64 = 500;
pub const MAX_LIMIT: i64 = 1000;

pub const SYNCED_TABLES: &[&str] = &[
    "account_preference",
    "active_challenge",
    "canvas_document",
    "challenge_completion",
    "outfit_template",
    "item_cutout",
    "item_fingerprint",
    "item_illustration",
    "photo",
    "photo_derivative",
    "wardrobe_item",
    "wardrobe_item_conflict",
    "wear_record",
];

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Change {
    /// The feed position of this record; the cursor is the last one you received.
    pub change_seq: i64,
    #[serde(flatten)]
    pub record: Record,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(tag = "kind", content = "record", rename_all = "camelCase")]
pub enum Record {
    WardrobeItem(records::WardrobeItem),
    ItemFingerprint(records::ItemFingerprint),
    ItemCutout(records::ItemCutout),
    ItemIllustration(records::ItemIllustration),
    OutfitTemplate(records::OutfitTemplate),
    WardrobeItemConflict(records::WardrobeItemConflict),
    Photo(records::Photo),
    PhotoDerivative(records::PhotoDerivative),
    CanvasDocument(records::CanvasDocument),
    ChallengeCompletion(records::ChallengeCompletion),
    ActiveChallenge(records::ActiveChallenge),
    WearRecord(records::WearRecord),
    AccountPreference(records::AccountPreference),
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn since(
    pool: &PgPool,
    account_id: Uuid,
    from: i64,
    limit: i64,
) -> Result<(Vec<Change>, i64), Error> {
    let limit = limit.clamp(1, MAX_LIMIT);
    let mut changes = Vec::new();
    items(pool, account_id, from, limit, &mut changes).await?;
    photos(pool, account_id, from, limit, &mut changes).await?;
    loop_and_preferences(pool, account_id, from, limit, &mut changes).await?;

    let page = page(changes, usize::try_from(limit).unwrap_or(usize::MAX));
    let next = page.last().map_or(from, |change| change.change_seq);
    Ok((page, next))
}

fn page(mut changes: Vec<Change>, limit: usize) -> Vec<Change> {
    changes.sort_by_key(|change| change.change_seq);
    if let Some(repeated) = changes
        .windows(2)
        .find(|pair| pair[0].change_seq == pair[1].change_seq)
    {
        tracing::error!(
            change_seq = repeated[0].change_seq,
            "two rows share a feed position; a page boundary between them would hide one"
        );
    }
    changes.truncate(limit);
    changes
}

// ---------------------------------------------------------------------- items

async fn items(
    pool: &PgPool,
    account: Uuid,
    from: i64,
    limit: i64,
    out: &mut Vec<Change>,
) -> Result<(), Error> {
    out.extend(
        records::fetch(pool, records::WARDROBE_ITEM, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::WardrobeItem| Change {
                change_seq: row.change_seq,
                record: Record::WardrobeItem(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::ITEM_FINGERPRINT, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::ItemFingerprint| Change {
                change_seq: row.change_seq,
                record: Record::ItemFingerprint(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::ITEM_CUTOUT, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::ItemCutout| Change {
                change_seq: row.change_seq,
                record: Record::ItemCutout(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::ITEM_ILLUSTRATION, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::ItemIllustration| Change {
                change_seq: row.change_seq,
                record: Record::ItemIllustration(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::OUTFIT_TEMPLATE, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::OutfitTemplate| Change {
                change_seq: row.change_seq,
                record: Record::OutfitTemplate(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::WARDROBE_ITEM_CONFLICT, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::WardrobeItemConflict| Change {
                change_seq: row.change_seq,
                record: Record::WardrobeItemConflict(row),
            }),
    );
    Ok(())
}

// --------------------------------------------------------------------- photos

async fn photos(
    pool: &PgPool,
    account: Uuid,
    from: i64,
    limit: i64,
    out: &mut Vec<Change>,
) -> Result<(), Error> {
    out.extend(
        records::fetch(pool, records::PHOTO, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::Photo| Change {
                change_seq: row.change_seq,
                record: Record::Photo(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::PHOTO_DERIVATIVE, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::PhotoDerivative| Change {
                change_seq: row.change_seq,
                record: Record::PhotoDerivative(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::CANVAS_DOCUMENT, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::CanvasDocument| Change {
                change_seq: row.change_seq,
                record: Record::CanvasDocument(row),
            }),
    );
    Ok(())
}

// ------------------------------------------------------- the loop, and the rest

async fn loop_and_preferences(
    pool: &PgPool,
    account: Uuid,
    from: i64,
    limit: i64,
    out: &mut Vec<Change>,
) -> Result<(), Error> {
    out.extend(
        records::fetch(pool, records::CHALLENGE_COMPLETION, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::ChallengeCompletion| Change {
                change_seq: row.change_seq,
                record: Record::ChallengeCompletion(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::ACTIVE_CHALLENGE, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::ActiveChallenge| Change {
                change_seq: row.change_seq,
                record: Record::ActiveChallenge(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::WEAR_RECORD, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::WearRecord| Change {
                change_seq: row.change_seq,
                record: Record::WearRecord(row),
            }),
    );
    out.extend(
        records::fetch(pool, records::ACCOUNT_PREFERENCE, account, from, limit)
            .await?
            .into_iter()
            .map(|row: records::AccountPreference| Change {
                change_seq: row.change_seq,
                record: Record::AccountPreference(row),
            }),
    );
    Ok(())
}

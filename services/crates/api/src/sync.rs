pub mod mutations;

use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;

pub const MAX_MUTATIONS: usize = 100;
pub const MAX_BODY_BYTES: usize = 1024 * 1024;

/// # Errors
///
/// Returns [`Error::BadRequest`] for an unknown mutation name or arguments that
/// do not match it, and whatever the mutation itself returns.
pub async fn apply(
    pool: &PgPool,
    account_id: Uuid,
    device: Option<Uuid>,
    name: &str,
    args: Value,
) -> Result<Value, Error> {
    match name {
        "completeChallenge" => mutations::complete_challenge::apply(pool, account_id, args).await,
        "deleteItem" => mutations::delete_item::apply(pool, account_id, args).await,
        "mergeItems" => mutations::merge_items::apply(pool, account_id, args).await,
        "resolveCompletion" => mutations::resolve_completion::apply(pool, account_id, args).await,
        "upsertItem" => mutations::upsert_item::apply_as(pool, account_id, device, args).await,
        "upsertPreferences" => mutations::upsert_preferences::apply(pool, account_id, args).await,
        _ => Err(Error::BadRequest),
    }
}

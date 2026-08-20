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
    name: &str,
    args: Value,
) -> Result<Value, Error> {
    match name {
        "deleteItem" => mutations::delete_item::apply(pool, account_id, args).await,
        "upsertPreferences" => mutations::upsert_preferences::apply(pool, account_id, args).await,
        _ => Err(Error::BadRequest),
    }
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn current_change_seq(pool: &PgPool, account_id: Uuid) -> Result<i64, Error> {
    sqlx::query_scalar::<_, i64>("select change_seq from account where id = $1")
        .bind(account_id)
        .fetch_one(pool)
        .await
        .map_err(Error::from)
}

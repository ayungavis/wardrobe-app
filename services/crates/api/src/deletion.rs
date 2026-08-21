use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_storage::Storage;

use crate::error::Error;

const MAX_ROUNDS: usize = 8;

/// # Errors
///
/// Returns [`Error::Unavailable`] when the account owns objects and no store is
/// configured, when the store refuses a delete, or when new objects keep
/// arriving faster than they can be swept.
pub async fn account(
    pool: &PgPool,
    storage: Option<&Storage>,
    account_id: Uuid,
) -> Result<(), Error> {
    for _ in 0..MAX_ROUNDS {
        let present: Option<(Uuid,)> = sqlx::query_as("select id from account where id = $1")
            .bind(account_id)
            .fetch_optional(pool)
            .await?;
        if present.is_none() {
            return Ok(());
        }

        let keys: Vec<String> =
            sqlx::query_scalar("select storage_key from media_object where account_id = $1")
                .bind(account_id)
                .fetch_all(pool)
                .await?;

        if !keys.is_empty() {
            storage
                .ok_or(Error::Unavailable)?
                .delete_many(&keys)
                .await?;
        }

        let swept = sqlx::query(
            "delete from account
              where id = $1
                and not exists (
                    select 1 from media_object
                     where account_id = $1 and not (storage_key = any($2))
                )",
        )
        .bind(account_id)
        .bind(&keys)
        .execute(pool)
        .await?;

        if swept.rows_affected() > 0 {
            return Ok(());
        }
    }

    Err(Error::Unavailable)
}

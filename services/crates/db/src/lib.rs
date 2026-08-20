// Queries here use the runtime API rather than `sqlx::query!`, so
// nothing needs a live database or a committed `.sqlx` cache to compile. Move to
// the macros once there are enough queries for compile-time SQL checking to pay
// for the offline-cache workflow.

use sqlx::PgConnection;
use sqlx::migrate::Migrator;
use uuid::Uuid;

pub static MIGRATOR: Migrator = sqlx::migrate!("../../migrations");

/// # Errors
///
/// Returns [`sqlx::Error::RowNotFound`] when the account does not exist.
pub async fn next_change_seq(conn: &mut PgConnection, account_id: Uuid) -> sqlx::Result<i64> {
    sqlx::query_scalar::<_, i64>(
        "update account
            set change_seq = change_seq + 1,
                updated_at = now()
          where id = $1
      returning change_seq",
    )
    .bind(account_id)
    .fetch_one(conn)
    .await
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ClaimedJob {
    pub id: Uuid,
    pub kind: String,
    pub payload: serde_json::Value,
    pub attempts: i32,
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn claim_job(conn: &mut PgConnection, kind: &str) -> sqlx::Result<Option<ClaimedJob>> {
    sqlx::query_as::<_, ClaimedJob>(
        "update job
            set status     = 'running',
                attempts   = attempts + 1,
                started_at = now(),
                updated_at = now()
          where id = (
                select id
                  from job
                 where kind = $1
                   and status = 'pending'
                   and run_after <= now()
                 order by run_after
                   for update skip locked
                 limit 1
          )
      returning id, kind, payload, attempts",
    )
    .bind(kind)
    .fetch_optional(conn)
    .await
}

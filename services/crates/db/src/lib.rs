//! Schema and the two database operations whose correctness is subtle enough
//! that the rest of the backend should never re-implement them.
//!
//! Everything else about the schema is documented in `docs/backend-schema.md`.
//!
//! ponytail: queries here use the runtime API rather than `sqlx::query!`, so
//! nothing needs a live database or a committed `.sqlx` cache to compile. Move
//! to the macros once there are enough queries for compile-time SQL checking to
//! pay for the offline-cache workflow.

use sqlx::PgConnection;
use sqlx::migrate::Migrator;
use uuid::Uuid;

/// The migrations that define the schema, embedded so tests and the binaries
/// apply exactly the same files.
pub static MIGRATOR: Migrator = sqlx::migrate!("../../migrations");

/// Allocates this account's next position in its change feed.
///
/// The pull cursor is `change_seq`, not `updated_at`, because `now()` is the
/// transaction's *start* time: two concurrent writers can commit in the reverse
/// order of their timestamps, and a client that advanced past the later-visible
/// row would never sync it (FR-059). Bumping a counter on the account row makes
/// the feed totally ordered, at the cost of serialising writes for one account —
/// which is one person's phone.
///
/// Must be called inside the same transaction as the domain write.
///
/// # Errors
///
/// Returns [`sqlx::Error::RowNotFound`] when the account does not exist, and any
/// other database error unchanged.
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

/// A job this worker now owns.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ClaimedJob {
    pub id: Uuid,
    pub kind: String,
    pub payload: serde_json::Value,
    pub attempts: i32,
}

/// Takes the next runnable job of `kind`, or nothing if none is due.
///
/// `for update skip locked` is what lets several workers share one table without
/// a broker: a row already locked by another claimant is stepped over instead of
/// waited on, so two workers can never hold the same job.
///
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

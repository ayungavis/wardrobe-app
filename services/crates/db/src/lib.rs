// ponytail: queries here use the runtime API rather than `sqlx::query!`, so
// nothing needs a live database or a committed `.sqlx` cache to compile. Move to
// the macros once there are enough queries for compile-time SQL checking to pay
// for the offline-cache workflow.

use sqlx::PgConnection;
use sqlx::migrate::Migrator;
use uuid::Uuid;

pub static MIGRATOR: Migrator = sqlx::migrate!("../../migrations");

pub const ILLUSTRATION: &str = "illustration";
pub const STYLISE_ILLUSTRATION: &str = "styliseIllustration";
pub const STYLE_VERSION: &str = "v1";

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

/// # Errors
///
/// Returns any database error unchanged.
pub async fn reclaim_stalled(
    conn: &mut PgConnection,
    kind: &str,
    older_than: chrono::Duration,
) -> sqlx::Result<u64> {
    sqlx::query(
        "update job
            set status = 'pending', updated_at = now()
          where kind = $1
            and status = 'running'
            and started_at < now() - $2::interval",
    )
    .bind(kind)
    .bind(older_than)
    .execute(conn)
    .await
    .map(|done| done.rows_affected())
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

// ---------------------------------------------------------------- errors

pub struct ErrorFacts {
    pub code: &'static str,
    pub sqlstate: Option<String>,
    pub constraint: Option<String>,
}

#[must_use]
pub fn error_facts(error: &sqlx::Error) -> ErrorFacts {
    let (code, database) = match error {
        sqlx::Error::RowNotFound => ("row_not_found", None),
        sqlx::Error::PoolTimedOut => ("pool_timed_out", None),
        sqlx::Error::PoolClosed => ("pool_closed", None),
        sqlx::Error::Io(_) => ("io", None),
        sqlx::Error::Tls(_) => ("tls", None),
        sqlx::Error::Protocol(_) => ("protocol", None),
        sqlx::Error::Configuration(_) => ("configuration", None),
        sqlx::Error::ColumnNotFound(_) | sqlx::Error::ColumnIndexOutOfBounds { .. } => {
            ("column_not_found", None)
        }
        sqlx::Error::ColumnDecode { .. } | sqlx::Error::Decode(_) => ("decode", None),
        sqlx::Error::Migrate(_) => ("migrate", None),
        sqlx::Error::Database(source) => ("database", Some(source)),
        _ => ("other", None),
    };

    ErrorFacts {
        code,
        sqlstate: database.and_then(|source| source.code().map(std::borrow::Cow::into_owned)),
        constraint: database.and_then(|source| source.constraint().map(str::to_owned)),
    }
}

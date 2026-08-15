use sqlx::PgPool;

/// Shared, cheap to clone: `PgPool` is an `Arc` internally, and handlers run on
/// any thread.
#[derive(Debug, Clone)]
pub struct AppState {
    pub pool: PgPool,
}

impl AppState {
    #[must_use]
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

use sqlx::PgPool;

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

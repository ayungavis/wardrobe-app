use std::sync::Arc;

use sqlx::PgPool;

use crate::auth::apple;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub apple: Arc<apple::Verifier>,
    pub storage: Option<Arc<wardrobe_storage::Storage>>,
}

impl AppState {
    #[must_use]
    pub fn new(
        pool: PgPool,
        apple: Arc<apple::Verifier>,
        storage: Option<Arc<wardrobe_storage::Storage>>,
    ) -> Self {
        Self {
            pool,
            apple,
            storage,
        }
    }
}

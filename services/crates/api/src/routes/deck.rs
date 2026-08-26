use axum::Json;
use axum::extract::{Query, State};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};

use crate::auth::Session;
use crate::deck::{self, DeckCard};
use crate::error::Error;
use crate::state::AppState;

#[derive(Debug, Deserialize, IntoParams)]
#[serde(rename_all = "camelCase")]
#[into_params(parameter_in = Query)]
pub struct DeckQuery {
    /// The user-local calendar date, computed on the device.
    pub local_date: NaiveDate,
    /// The device's locale, used to pick curated copy; defaults to `en`.
    pub locale: Option<String>,
}

/// The day's challenge cards.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct DeckResponse {
    pub local_date: NaiveDate,
    /// `generated` or `curated`; `curated` means generation was unavailable.
    pub source: &'static str,
    pub cards: Vec<DeckCard>,
}

/// Returns the day's generated deck, or the curated catalog when none exists.
#[utoipa::path(
    get,
    path = "/v1/challenges/deck",
    tag = "challenge",
    security(("session" = [])),
    params(DeckQuery),
    responses(
        (status = 200, description = "The day's deck", body = DeckResponse),
        (status = 400, description = "Unusable query", body = crate::error::ErrorBody),
        (status = 401, description = "Missing or unusable token", body = crate::error::ErrorBody),
    )
)]
pub async fn deck(
    State(state): State<AppState>,
    session: Session,
    Query(query): Query<DeckQuery>,
) -> Result<Json<DeckResponse>, Error> {
    let locale = query.locale.as_deref().unwrap_or("en");
    let deck = deck::for_day(&state.pool, session.account_id, query.local_date, locale).await?;

    Ok(Json(DeckResponse {
        local_date: query.local_date,
        source: if deck.generated {
            "generated"
        } else {
            "curated"
        },
        cards: deck.cards,
    }))
}

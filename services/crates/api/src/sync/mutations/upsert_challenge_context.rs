use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;

const LOCALE_LIMIT: usize = 16;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    time_zone: String,
    #[serde(default)]
    locale: Option<String>,
    #[serde(default)]
    weather: Option<WeatherArgs>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WeatherArgs {
    local_date: NaiveDate,
    condition: String,
    high_c: i16,
    low_c: i16,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Stored {
    #[sqlx(rename = "anonymous_id")]
    device_id: Uuid,
    time_zone: Option<String>,
    weather_local_date: Option<NaiveDate>,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments or a time zone this
/// database does not know, and [`Error::NotFound`] when the device is not this
/// account's.
pub async fn apply_as(
    pool: &PgPool,
    account_id: Uuid,
    device: Option<Uuid>,
    args: Value,
) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;
    let device = device.ok_or(Error::BadRequest)?;

    let (known,): (bool,) =
        sqlx::query_as("select exists (select 1 from pg_timezone_names where name = $1)")
            .bind(&args.time_zone)
            .fetch_one(pool)
            .await?;
    if !known {
        return Err(Error::BadRequest);
    }

    let locale = args
        .locale
        .map(|locale| locale.trim().chars().take(LOCALE_LIMIT).collect::<String>())
        .filter(|locale| !locale.is_empty());
    let weather = args.weather;

    let stored: Option<Stored> = sqlx::query_as(
        "update account_device
            set time_zone          = $2,
                locale             = coalesce($3, locale),
                weather_local_date = coalesce($4, weather_local_date),
                weather_condition  = coalesce($5, weather_condition),
                weather_high_c     = coalesce($6, weather_high_c),
                weather_low_c      = coalesce($7, weather_low_c),
                last_seen_at       = now()
          where anonymous_id = $1 and account_id = $8
      returning anonymous_id, time_zone, weather_local_date",
    )
    .bind(device)
    .bind(&args.time_zone)
    .bind(locale)
    .bind(weather.as_ref().map(|weather| weather.local_date))
    .bind(weather.as_ref().map(|weather| weather.condition.as_str()))
    .bind(weather.as_ref().map(|weather| weather.high_c))
    .bind(weather.as_ref().map(|weather| weather.low_c))
    .bind(account_id)
    .fetch_optional(pool)
    .await?;

    let stored = stored.ok_or(Error::NotFound)?;
    serde_json::to_value(&stored).map_err(|_| Error::BadRequest)
}

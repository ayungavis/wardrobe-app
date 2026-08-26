use rust_decimal::Decimal;
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_db::ClaimedJob;

pub struct Provider {
    pub client: reqwest::Client,
    pub base_url: String,
    pub api_key: String,
}

pub struct Config {
    pub active_model: String,
    pub alternate_model: Option<String>,
    pub prompt_version: String,
    pub params: Value,
}

impl Config {
    #[must_use]
    pub fn text(&self, key: &str) -> Option<String> {
        self.params
            .get(key)
            .and_then(|value| match value {
                Value::String(text) => Some(text.clone()),
                _ => None,
            })
            .filter(|text| !text.is_empty())
    }

    #[must_use]
    pub fn integer(&self, key: &str) -> Option<i64> {
        self.params.get(key).and_then(|value| match value {
            Value::Number(number) => number.as_i64(),
            Value::String(text) => text.parse().ok(),
            _ => None,
        })
    }

    #[must_use]
    pub fn number(&self, key: &str) -> Option<f64> {
        self.params.get(key).and_then(|value| match value {
            Value::Number(number) => number.as_f64(),
            Value::String(text) => text.parse().ok(),
            _ => None,
        })
    }
}

/// # Errors
///
/// Returns any database error unchanged.
pub async fn ready(pool: &PgPool, capability: &str) -> sqlx::Result<bool> {
    let (enabled,): (bool,) = sqlx::query_as(
        "select exists (
             select 1 from ai_model_config
              where capability = $1 and enabled
         ) and exists (
             select 1 from ai_provider_allowlist where revoked_at is null
         )",
    )
    .bind(capability)
    .fetch_one(pool)
    .await?;
    Ok(enabled)
}

/// # Errors
///
/// Returns `capability_disabled` when no enabled row exists, `database` otherwise.
pub async fn config(pool: &PgPool, capability: &str) -> Result<Config, &'static str> {
    let row: Option<(String, Option<String>, String, Value)> = sqlx::query_as(
        "select active_model, alternate_model, prompt_version, params
           from ai_model_config
          where capability = $1 and enabled",
    )
    .bind(capability)
    .fetch_optional(pool)
    .await
    .map_err(|_| "database")?;

    let (active_model, alternate_model, prompt_version, params) =
        row.ok_or("capability_disabled")?;
    Ok(Config {
        active_model,
        alternate_model,
        prompt_version,
        params,
    })
}

/// # Errors
///
/// Returns `database` when a limit or its counter cannot be read.
pub async fn within_limits(
    pool: &PgPool,
    capability: &str,
    account: Uuid,
) -> Result<bool, &'static str> {
    let limits: Vec<(String, i32, Option<i64>, Option<Decimal>)> = sqlx::query_as(
        "select scope, window_seconds, max_requests, max_cost_usd
           from ai_usage_limit
          where enabled and (capability is null or capability = $1)",
    )
    .bind(capability)
    .fetch_all(pool)
    .await
    .map_err(|_| "database")?;

    for (scope, window_seconds, max_requests, max_cost_usd) in limits {
        let scoped = (scope == "account").then_some(account);
        let (requests, cost): (i64, Option<Decimal>) = sqlx::query_as(
            "select count(*), coalesce(sum(cost_usd), 0)
               from ai_inference_attempt
              where capability = $1
                and created_at > now() - make_interval(secs => $2)
                and ($3::uuid is null or account_id = $3)",
        )
        .bind(capability)
        .bind(f64::from(window_seconds))
        .bind(scoped)
        .fetch_one(pool)
        .await
        .map_err(|_| "database")?;

        if max_requests.is_some_and(|max| requests >= max) {
            return Ok(false);
        }
        if max_cost_usd.is_some_and(|max| cost.unwrap_or_default() >= max) {
            return Ok(false);
        }
    }

    Ok(true)
}

pub struct Pinned {
    pub model: String,
    pub seed: i64,
    pub attempt_no: i32,
    pub another_model_available: bool,
    pub quality_attempts_left: bool,
}

#[must_use]
pub fn fresh_seed() -> i64 {
    let bytes = Uuid::now_v7().into_bytes();
    let raw = u32::from_be_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]);
    i64::from(raw & 0x7FFF_FFFF)
}

/// # Errors
///
/// Returns `database` when earlier attempts cannot be read.
pub async fn pin(
    pool: &PgPool,
    job: Uuid,
    active_model: &str,
    alternate_model: Option<&str>,
    quality_attempts: i64,
) -> Result<Pinned, &'static str> {
    let earlier: Vec<(String, Option<i64>, String, Option<i32>)> = sqlx::query_as(
        "select model, seed, status, http_status from ai_inference_attempt
          where job_id = $1 order by attempt_no",
    )
    .bind(job)
    .fetch_all(pool)
    .await
    .map_err(|_| "database")?;

    let attempt_no = i32::try_from(earlier.len()).unwrap_or(i32::MAX) + 1;
    let invalid_so_far = earlier
        .iter()
        .filter(|(_, _, status, _)| status == "invalid_output")
        .count();
    let invalid_so_far = i64::try_from(invalid_so_far).unwrap_or(i64::MAX);
    let unused_alternate = alternate_model
        .filter(|alternate| !earlier.iter().any(|(model, _, _, _)| model == alternate));

    let Some((first_model, first_seed, last_status, last_http)) = earlier.last() else {
        return Ok(Pinned {
            model: active_model.to_owned(),
            seed: fresh_seed(),
            attempt_no,
            another_model_available: alternate_model.is_some(),
            quality_attempts_left: quality_attempts > 0,
        });
    };

    let escalating = matches!(last_status.as_str(), "refused" | "invalid_output")
        || matches!(last_http, Some(402 | 429));
    let (model, seed) = match unused_alternate {
        Some(alternate) if escalating => (alternate.to_owned(), fresh_seed()),
        _ => (first_model.clone(), first_seed.unwrap_or_else(fresh_seed)),
    };

    Ok(Pinned {
        model,
        seed,
        attempt_no,
        another_model_available: unused_alternate.is_some(),
        quality_attempts_left: invalid_so_far < quality_attempts,
    })
}

pub struct Accounting<'a> {
    pub status: &'a str,
    pub provider_route: Option<String>,
    pub latency_ms: Option<i32>,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub http_status: Option<i32>,
}

/// # Errors
///
/// Returns `database` when the attempt cannot be recorded.
pub async fn record(
    pool: &PgPool,
    capability: &str,
    job: &ClaimedJob,
    account: Uuid,
    pinned: &Pinned,
    prompt_version: &str,
    accounting: &Accounting<'_>,
) -> Result<(), &'static str> {
    sqlx::query(
        "insert into ai_inference_attempt
             (id, account_id, job_id, capability, attempt_no, model, prompt_version,
              provider_route, status, latency_ms, input_tokens, output_tokens, seed,
              http_status)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)",
    )
    .bind(Uuid::now_v7())
    .bind(account)
    .bind(job.id)
    .bind(capability)
    .bind(pinned.attempt_no)
    .bind(&pinned.model)
    .bind(prompt_version)
    .bind(accounting.provider_route.as_ref())
    .bind(accounting.status)
    .bind(accounting.latency_ms)
    .bind(accounting.input_tokens)
    .bind(accounting.output_tokens)
    .bind(pinned.seed)
    .bind(accounting.http_status)
    .execute(pool)
    .await
    .map(|_| ())
    .map_err(|_| "database")
}

#[cfg(test)]
mod tests {
    use super::fresh_seed;

    #[test]
    fn a_seed_always_fits_the_providers_int32() {
        for _ in 0..100 {
            assert!(
                fresh_seed() <= i64::from(i32::MAX),
                "the provider refuses any seed above 2147483647, and the uuid \
                 variant byte would otherwise set the top bit every single time"
            );
        }
    }
}

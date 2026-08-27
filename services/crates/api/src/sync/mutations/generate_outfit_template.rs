use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Error;

const TEMPLATES: [&str; 3] = ["lookbook", "blisterGreen", "blisterCream"];

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    request_id: Uuid,
    template: String,
    person_media_id: Uuid,
    #[serde(default)]
    garments: Vec<Garment>,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Garment {
    media_id: Uuid,
    name: Option<String>,
    wears: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Queued {
    request_id: Uuid,
    template: String,
    status: &'static str,
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments and [`Error::NotFound`]
/// when this account has no such completion.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;
    if !TEMPLATES.contains(&args.template.as_str()) {
        return Err(Error::BadRequest);
    }

    let mut media: Vec<Uuid> = vec![args.person_media_id];
    media.extend(args.garments.iter().map(|garment| garment.media_id));

    let mut tx = pool.begin().await?;
    let owned: i64 = sqlx::query_scalar(
        "select count(*) from media_object where id = any($1) and account_id = $2",
    )
    .bind(&media)
    .bind(account_id)
    .fetch_one(&mut *tx)
    .await?;
    if owned != i64::try_from(media.len()).unwrap_or(i64::MAX) {
        return Err(Error::NotFound);
    }

    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key, payload)
         values ($1, $2, $3, $4, $5)
         on conflict (kind, dedupe_key) do update
            set status = 'pending',
                attempts = 0,
                run_after = now(),
                started_at = null,
                finished_at = null,
                last_error_code = null,
                payload = excluded.payload",
    )
    .bind(Uuid::now_v7())
    .bind(account_id)
    .bind(wardrobe_db::OUTFIT_TEMPLATE)
    .bind(format!("{}:{}", args.request_id, args.template))
    .bind(serde_json::json!({
        "requestId": args.request_id.to_string(),
        "template": args.template,
        "personMediaId": args.person_media_id.to_string(),
        "garments": args.garments,
    }))
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    serde_json::to_value(Queued {
        request_id: args.request_id,
        template: args.template,
        status: "queued",
    })
    .map_err(|_| Error::BadRequest)
}

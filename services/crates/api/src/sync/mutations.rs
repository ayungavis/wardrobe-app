pub mod complete_challenge;
pub mod delete_item;
pub mod merge_items;
pub mod resolve_completion;
pub mod upsert_item;
pub mod upsert_preferences;

use serde::Deserialize;
use sqlx::{PgConnection, Postgres, Transaction};
use uuid::Uuid;

use crate::error::Error;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CutoutArgs {
    pub id: Uuid,
    pub media_object_id: Uuid,
    pub source_photo_id: Option<Uuid>,
}

pub(crate) async fn next(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
) -> Result<i64, Error> {
    let conn: &mut PgConnection = tx;
    wardrobe_db::next_change_seq(conn, account_id)
        .await
        .map_err(Error::from)
}

pub(crate) async fn write_cutout(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    item_id: Uuid,
    cutout: &CutoutArgs,
    fallback_source_photo: Option<Uuid>,
) -> Result<(), Error> {
    let seq = next(tx, account_id).await?;
    sqlx::query(
        "insert into item_cutout
             (id, account_id, item_id, media_object_id, source_photo_id, change_seq)
         values ($1, $2, $3, $4, $5, $6)
         on conflict (id) do nothing",
    )
    .bind(cutout.id)
    .bind(account_id)
    .bind(item_id)
    .bind(cutout.media_object_id)
    .bind(cutout.source_photo_id.or(fallback_source_photo))
    .bind(seq)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub(crate) async fn enqueue_illustrations(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    items: &[Uuid],
) -> Result<(), Error> {
    for item in items {
        sqlx::query(
            "insert into job (id, account_id, kind, dedupe_key, payload)
             values ($1, $2, $3, $4, jsonb_build_object('itemId', $5::text))
             on conflict (kind, dedupe_key) do nothing",
        )
        .bind(Uuid::now_v7())
        .bind(account_id)
        .bind(wardrobe_db::ILLUSTRATION)
        .bind(format!("{item}:{}", wardrobe_db::STYLE_VERSION))
        .bind(item.to_string())
        .execute(&mut **tx)
        .await?;

        let seq = next(tx, account_id).await?;
        sqlx::query(
            "update wardrobe_item set illustration_state = 'queued', change_seq = $2 where id = $1",
        )
        .bind(item)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

pub(crate) fn client_error(error: sqlx::Error) -> Error {
    match wardrobe_db::error_facts(&error).sqlstate.as_deref() {
        Some("23503" | "23514") => Error::BadRequest,
        Some("23505") => Error::Conflict,
        _ => Error::from(error),
    }
}

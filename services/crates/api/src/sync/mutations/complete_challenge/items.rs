use chrono::NaiveDate;
use serde::Deserialize;
use serde_json::{Map, Value, json};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::error::Error;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ItemArgs {
    id: Uuid,
    wear_id: Uuid,
    category: String,
    name: Option<String>,
    color: Option<String>,
    garment_type: Option<String>,
    description: Option<String>,
    source_photo_id: Option<Uuid>,
}

fn revisions(item: &ItemArgs) -> Value {
    let mut seeded = Map::new();
    for (field, present) in [
        ("name", item.name.is_some()),
        ("color", item.color.is_some()),
        ("garment_type", item.garment_type.is_some()),
        ("description", item.description.is_some()),
    ] {
        if present {
            seeded.insert(field.to_owned(), json!({ "rev": 1 }));
        }
    }
    Value::Object(seeded)
}

pub(super) async fn confirm(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    items: &[ItemArgs],
) -> Result<(), Error> {
    for item in items {
        let seq = super::next(tx, account_id).await?;
        sqlx::query(
            "insert into wardrobe_item
                 (id, account_id, category, name, color, garment_type, description,
                  attribute_revisions, change_seq)
             values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
             on conflict (id) do nothing",
        )
        .bind(item.id)
        .bind(account_id)
        .bind(&item.category)
        .bind(item.name.as_ref())
        .bind(item.color.as_ref())
        .bind(item.garment_type.as_ref())
        .bind(item.description.as_ref())
        .bind(revisions(item))
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

pub(super) async fn record_wears(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
    items: &[ItemArgs],
    completion_id: Uuid,
    worn_on: NaiveDate,
) -> Result<(), Error> {
    for item in items {
        let seq = super::next(tx, account_id).await?;
        sqlx::query(
            "insert into wear_record
                 (id, account_id, item_id, completion_id, source_photo_id, worn_on, change_seq)
             values ($1, $2, $3, $4, $5, $6, $7)
             on conflict (account_id, item_id, source_photo_id) do update
                set revision      = wear_record.revision + 1,
                    completion_id = excluded.completion_id,
                    worn_on       = excluded.worn_on,
                    change_seq    = excluded.change_seq",
        )
        .bind(item.wear_id)
        .bind(account_id)
        .bind(item.id)
        .bind(completion_id)
        .bind(item.source_photo_id)
        .bind(worn_on)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

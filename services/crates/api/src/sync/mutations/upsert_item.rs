use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use super::CutoutArgs;
use crate::error::Error;

type Tx<'a> = Transaction<'a, Postgres>;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    id: Uuid,
    category: Option<Field>,
    name: Option<Field>,
    color: Option<Field>,
    garment_type: Option<Field>,
    description: Option<Field>,
    cutout: Option<CutoutArgs>,
}

#[derive(Deserialize)]
struct Field {
    value: Option<String>,
    rev: i64,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Item {
    id: Uuid,
    #[serde(skip)]
    account_id: Uuid,
    category: String,
    name: Option<String>,
    color: Option<String>,
    garment_type: Option<String>,
    description: Option<String>,
    attribute_revisions: Value,
    illustration_state: String,
    change_seq: i64,
    deleted_at: Option<DateTime<Utc>>,
}

const COLUMNS: &str = "id, account_id, category, name, color, garment_type, description,
     attribute_revisions, illustration_state, change_seq, deleted_at";

struct Merged {
    values: [Option<String>; 5],
    revisions: Value,
    changed: bool,
    conflicts: Vec<Conflict>,
}

struct Conflict {
    field: &'static str,
    value: Option<String>,
    revision: i64,
}

fn named(args: &Args) -> [(&'static str, Option<&Field>); 5] {
    [
        ("category", args.category.as_ref()),
        ("name", args.name.as_ref()),
        ("color", args.color.as_ref()),
        ("garment_type", args.garment_type.as_ref()),
        ("description", args.description.as_ref()),
    ]
}

fn stored(item: &Item) -> [Option<String>; 5] {
    [
        Some(item.category.clone()),
        item.name.clone(),
        item.color.clone(),
        item.garment_type.clone(),
        item.description.clone(),
    ]
}

fn merge(item: &Item, args: &Args, device: Option<Uuid>) -> Merged {
    let mut values = stored(item);
    let mut revisions = item
        .attribute_revisions
        .as_object()
        .cloned()
        .unwrap_or_else(Map::new);
    let mut changed = false;
    let mut conflicts = Vec::new();

    for (index, (field, offered)) in named(args).into_iter().enumerate() {
        let Some(offered) = offered else { continue };
        let held = revisions
            .get(field)
            .and_then(|entry| entry.get("rev"))
            .and_then(Value::as_i64)
            .unwrap_or(0);

        if offered.rev > held {
            values[index].clone_from(&offered.value);
            revisions.insert(
                field.to_owned(),
                json!({ "rev": offered.rev, "origin": device }),
            );
            changed = true;
        } else if offered.rev == held && offered.value != values[index] {
            conflicts.push(Conflict {
                field,
                value: offered.value.clone(),
                revision: offered.rev,
            });
        }
    }

    Merged {
        values,
        revisions: Value::Object(revisions),
        changed,
        conflicts,
    }
}

/// # Errors
///
/// Returns [`Error::BadRequest`] for unusable arguments or a missing category on
/// a new item, and [`Error::Conflict`] when the id belongs to another account.
pub async fn apply(pool: &PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    apply_as(pool, account_id, None, args).await
}

/// # Errors
///
/// See [`apply`]. `device` is recorded as the origin of every revision it writes.
pub async fn apply_as(
    pool: &PgPool,
    account_id: Uuid,
    device: Option<Uuid>,
    args: Value,
) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;
    let mut tx = pool.begin().await?;

    let existing: Option<Item> = sqlx::query_as(&format!(
        "select {COLUMNS} from wardrobe_item where id = $1 for update"
    ))
    .bind(args.id)
    .fetch_optional(&mut *tx)
    .await?;

    let item = match existing {
        Some(item) if item.account_id != account_id => return Err(Error::Conflict),
        Some(item) if item.deleted_at.is_some() => item,
        Some(item) => update(&mut tx, account_id, device, &item, &args).await?,
        None => create(&mut tx, account_id, device, &args).await?,
    };

    if item.deleted_at.is_none()
        && let Some(cutout) = args.cutout.as_ref()
    {
        super::write_cutout(&mut tx, account_id, item.id, cutout, None).await?;
    }
    tx.commit().await?;

    serde_json::to_value(&item).map_err(|_| Error::BadRequest)
}

async fn update(
    tx: &mut Tx<'_>,
    account_id: Uuid,
    device: Option<Uuid>,
    item: &Item,
    args: &Args,
) -> Result<Item, Error> {
    let merged = merge(item, args, device);
    let mut current = Item { ..clone_of(item) };

    if merged.changed {
        let seq = super::next(tx, account_id).await?;
        current = sqlx::query_as(&format!(
            "update wardrobe_item
                set category = $2, name = $3, color = $4, garment_type = $5, description = $6,
                    attribute_revisions = $7, change_seq = $8
              where id = $1
          returning {COLUMNS}"
        ))
        .bind(item.id)
        .bind(merged.values[0].as_ref())
        .bind(merged.values[1].as_ref())
        .bind(merged.values[2].as_ref())
        .bind(merged.values[3].as_ref())
        .bind(merged.values[4].as_ref())
        .bind(&merged.revisions)
        .bind(seq)
        .fetch_one(&mut **tx)
        .await
        .map_err(super::client_error)?;
    }

    for conflict in merged.conflicts {
        let seq = super::next(tx, account_id).await?;
        sqlx::query(
            "insert into wardrobe_item_conflict
                 (id, account_id, item_id, field, value, revision, origin_device, change_seq)
             values ($1, $2, $3, $4, $5, $6, $7, $8)",
        )
        .bind(Uuid::now_v7())
        .bind(account_id)
        .bind(item.id)
        .bind(conflict.field)
        .bind(conflict.value)
        .bind(conflict.revision)
        .bind(device)
        .bind(seq)
        .execute(&mut **tx)
        .await
        .map_err(super::client_error)?;
    }

    Ok(current)
}

fn clone_of(item: &Item) -> Item {
    Item {
        id: item.id,
        account_id: item.account_id,
        category: item.category.clone(),
        name: item.name.clone(),
        color: item.color.clone(),
        garment_type: item.garment_type.clone(),
        description: item.description.clone(),
        attribute_revisions: item.attribute_revisions.clone(),
        illustration_state: item.illustration_state.clone(),
        change_seq: item.change_seq,
        deleted_at: item.deleted_at,
    }
}

async fn create(
    tx: &mut Tx<'_>,
    account_id: Uuid,
    device: Option<Uuid>,
    args: &Args,
) -> Result<Item, Error> {
    let category = args
        .category
        .as_ref()
        .and_then(|field| field.value.clone())
        .ok_or(Error::BadRequest)?;

    let mut revisions = Map::new();
    let mut values: [Option<String>; 5] = [Some(category), None, None, None, None];
    for (index, (field, offered)) in named(args).into_iter().enumerate() {
        let Some(offered) = offered else { continue };
        if index > 0 {
            values[index].clone_from(&offered.value);
        }
        revisions.insert(
            field.to_owned(),
            json!({ "rev": offered.rev, "origin": device }),
        );
    }

    let seq = super::next(tx, account_id).await?;
    let item: Item = sqlx::query_as(&format!(
        "insert into wardrobe_item
             (id, account_id, category, name, color, garment_type, description,
              attribute_revisions, change_seq)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         returning {COLUMNS}"
    ))
    .bind(args.id)
    .bind(account_id)
    .bind(values[0].as_ref())
    .bind(values[1].as_ref())
    .bind(values[2].as_ref())
    .bind(values[3].as_ref())
    .bind(values[4].as_ref())
    .bind(Value::Object(revisions))
    .bind(seq)
    .fetch_one(&mut **tx)
    .await
    .map_err(super::client_error)?;

    super::enqueue_illustrations(tx, account_id, &[item.id]).await?;
    Ok(item)
}

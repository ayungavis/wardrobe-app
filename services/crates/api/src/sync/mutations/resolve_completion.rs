use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::error::Error;

type Tx<'a> = Transaction<'a, Postgres>;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    completion_id: Uuid,
}

#[derive(Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
struct Completion {
    id: Uuid,
    #[serde(skip)]
    account_id: Uuid,
    status: String,
    local_date: NaiveDate,
    change_seq: i64,
    #[serde(skip)]
    deleted_at: Option<DateTime<Utc>>,
}

const COLUMNS: &str = "id, account_id, status, local_date, change_seq, deleted_at";

/// # Errors
///
/// Returns [`Error::NotFound`] when the account has no such live completion and
/// [`Error::Conflict`] when it belongs to someone else.
pub async fn apply(pool: &sqlx::PgPool, account_id: Uuid, args: Value) -> Result<Value, Error> {
    let args: Args = serde_json::from_value(args).map_err(|_| Error::BadRequest)?;
    let mut tx = pool.begin().await?;

    sqlx::query("select id from account where id = $1 for update")
        .bind(account_id)
        .execute(&mut *tx)
        .await?;

    let winner: Option<Completion> = sqlx::query_as(&format!(
        "select {COLUMNS} from challenge_completion where id = $1"
    ))
    .bind(args.completion_id)
    .fetch_optional(&mut *tx)
    .await?;

    let winner = match winner {
        Some(row) if row.account_id != account_id => return Err(Error::Conflict),
        Some(row) if row.deleted_at.is_some() => return Err(Error::NotFound),
        Some(row) => row,
        None => return Err(Error::NotFound),
    };

    let demoted = demote_the_others(&mut tx, account_id, &winner).await?;
    let promoted = winner.status != "canonical";
    if demoted.is_empty() && !promoted {
        tx.commit().await?;
        return serialize(&winner);
    }

    let winner = if promoted {
        promote(&mut tx, account_id, winner.id).await?
    } else {
        winner
    };

    let mut changed = demoted;
    if promoted {
        changed.push(winner.id);
    }
    for completion in &changed {
        bump_wears(&mut tx, account_id, *completion).await?;
    }

    tx.commit().await?;
    serialize(&winner)
}

fn serialize(completion: &Completion) -> Result<Value, Error> {
    serde_json::to_value(completion).map_err(|_| Error::BadRequest)
}

async fn demote_the_others(
    tx: &mut Tx<'_>,
    account_id: Uuid,
    winner: &Completion,
) -> Result<Vec<Uuid>, Error> {
    let others: Vec<(Uuid,)> = sqlx::query_as(
        "select id from challenge_completion
          where account_id = $1 and local_date = $2 and id <> $3
            and deleted_at is null and status <> 'superseded'",
    )
    .bind(account_id)
    .bind(winner.local_date)
    .bind(winner.id)
    .fetch_all(&mut **tx)
    .await?;

    let mut demoted = Vec::with_capacity(others.len());
    for (id,) in others {
        let seq = super::next(tx, account_id).await?;
        sqlx::query(
            "update challenge_completion set status = 'superseded', change_seq = $2 where id = $1",
        )
        .bind(id)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
        demoted.push(id);
    }

    Ok(demoted)
}

async fn promote(tx: &mut Tx<'_>, account_id: Uuid, id: Uuid) -> Result<Completion, Error> {
    let seq = super::next(tx, account_id).await?;
    sqlx::query_as(&format!(
        "update challenge_completion set status = 'canonical', change_seq = $2
          where id = $1
      returning {COLUMNS}"
    ))
    .bind(id)
    .bind(seq)
    .fetch_one(&mut **tx)
    .await
    .map_err(super::client_error)
}

async fn bump_wears(tx: &mut Tx<'_>, account_id: Uuid, completion: Uuid) -> Result<(), Error> {
    let wears: Vec<(Uuid,)> = sqlx::query_as(
        "select id from wear_record where completion_id = $1 and deleted_at is null",
    )
    .bind(completion)
    .fetch_all(&mut **tx)
    .await?;

    for (wear,) in wears {
        let seq = super::next(tx, account_id).await?;
        sqlx::query("update wear_record set change_seq = $2 where id = $1")
            .bind(wear)
            .bind(seq)
            .execute(&mut **tx)
            .await?;
    }
    Ok(())
}

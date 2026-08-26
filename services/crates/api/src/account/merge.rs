use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::changes::SYNCED_TABLES;
use crate::error::Error;

const PREFERENCE: &str = "account_preference";

pub const UNSEQUENCED_TABLES: &[&str] = &[
    "account_device",
    "ai_inference_attempt",
    "challenge_card",
    "job",
    "media_object",
];

pub const EXEMPT_TABLES: &[&str] = &["session"];

pub fn sequenced_tables() -> impl Iterator<Item = &'static str> {
    SYNCED_TABLES
        .iter()
        .copied()
        .filter(|name| *name != PREFERENCE)
}

/// # Errors
///
/// Returns [`Error::MergeIncomplete`] when a table was left behind, and any
/// database error unchanged.
pub async fn into(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<(), Error> {
    lock_both(tx, destination, source).await?;
    let demoted = resolve_same_day(tx, destination, source).await?;
    let stale = resolve_active_challenge(tx, destination, source).await?;

    reissue_and_move(tx, destination, source).await?;
    move_unsequenced(tx, destination, source).await?;
    merge_preferences(tx, destination, source).await?;

    for completion in demoted {
        bump_completion(tx, destination, completion).await?;
    }
    if let Some(challenge) = stale {
        bump_active_challenge(tx, destination, challenge).await?;
    }
    drain(tx, source).await
}

async fn lock_both(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<(), Error> {
    let held: Vec<(Uuid,)> =
        sqlx::query_as("select id from account where id = any($1) order by id for update")
            .bind(vec![destination, source])
            .fetch_all(&mut **tx)
            .await?;

    if held.len() == 2 {
        Ok(())
    } else {
        Err(Error::NotFound)
    }
}

async fn resolve_same_day(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<Vec<Uuid>, Error> {
    sqlx::query(&demotion("$2", "$1", "<="))
        .bind(destination)
        .bind(source)
        .execute(&mut **tx)
        .await?;

    let demoted: Vec<(Uuid,)> =
        sqlx::query_as(&format!("{} returning loser.id", demotion("$1", "$2", "<")))
            .bind(destination)
            .bind(source)
            .fetch_all(&mut **tx)
            .await?;

    Ok(demoted.into_iter().map(|(id,)| id).collect())
}

fn demotion(loser: &str, winner: &str, order: &str) -> String {
    format!(
        "update challenge_completion loser
            set status = 'conflicting'
          where loser.account_id = {loser}
            and loser.status = 'canonical'
            and loser.deleted_at is null
            and exists (
                select 1
                  from challenge_completion winner
                 where winner.account_id = {winner}
                   and winner.local_date = loser.local_date
                   and winner.status = 'canonical'
                   and winner.deleted_at is null
                   and winner.completed_at {order} loser.completed_at
            )"
    )
}

async fn resolve_active_challenge(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<Option<Uuid>, Error> {
    let held = live_challenge(tx, destination).await?;
    let arriving = live_challenge(tx, source).await?;

    let (Some((held_id, held_at)), Some((arriving_id, arriving_at))) = (held, arriving) else {
        return Ok(None);
    };
    let stale = if arriving_at > held_at {
        held_id
    } else {
        arriving_id
    };

    sqlx::query("update active_challenge set deleted_at = now() where id = $1")
        .bind(stale)
        .execute(&mut **tx)
        .await?;
    Ok((stale == held_id).then_some(stale))
}

async fn live_challenge(
    tx: &mut Transaction<'_, Postgres>,
    account_id: Uuid,
) -> Result<Option<(Uuid, DateTime<Utc>)>, Error> {
    sqlx::query_as(
        "select id, accepted_at from active_challenge
          where account_id = $1 and deleted_at is null",
    )
    .bind(account_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(Error::from)
}

async fn reissue_and_move(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<(), Error> {
    let inventory = inventory(tx, source).await?;
    let Ok(count) = i64::try_from(inventory.len()) else {
        return Err(Error::MergeIncomplete);
    };
    if count == 0 {
        return Ok(());
    }

    let last = wardrobe_db::reserve_change_seq(tx, destination, count).await?;
    let moves: Vec<(String, Uuid, i64)> = inventory
        .into_iter()
        .zip(last - count + 1..)
        .map(|((table, id), seq)| (table, id, seq))
        .collect();

    for table in sequenced_tables() {
        let ids: Vec<Uuid> = moves
            .iter()
            .filter(|(name, ..)| name == table)
            .map(|&(_, id, _)| id)
            .collect();
        if ids.is_empty() {
            continue;
        }
        let seqs: Vec<i64> = moves
            .iter()
            .filter(|(name, ..)| name == table)
            .map(|&(.., seq)| seq)
            .collect();

        // SAFETY: `table` is one of the compile-time constants in `SYNCED_TABLES`,
        // so the interpolation cannot carry request data into the statement.
        sqlx::query(&format!(
            "update {table}
                set account_id = $1, change_seq = arriving.seq
               from unnest($2::uuid[], $3::bigint[]) as arriving (id, seq)
              where {table}.id = arriving.id and {table}.account_id = $4"
        ))
        .bind(destination)
        .bind(&ids)
        .bind(&seqs)
        .bind(source)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

async fn inventory(
    tx: &mut Transaction<'_, Postgres>,
    source: Uuid,
) -> Result<Vec<(String, Uuid)>, Error> {
    let branches: Vec<String> = sequenced_tables()
        .map(|table| {
            format!("select '{table}' as source_table, id, change_seq from {table} where account_id = $1")
        })
        .collect();
    let sql = format!(
        "{} order by change_seq, source_table, id",
        branches.join(" union all ")
    );

    let rows: Vec<(String, Uuid, i64)> = sqlx::query_as(&sql)
        .bind(source)
        .fetch_all(&mut **tx)
        .await?;
    Ok(rows.into_iter().map(|(table, id, _)| (table, id)).collect())
}

async fn move_unsequenced(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<(), Error> {
    for table in UNSEQUENCED_TABLES {
        sqlx::query(&format!(
            "update {table} set account_id = $1 where account_id = $2"
        ))
        .bind(destination)
        .bind(source)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

async fn merge_preferences(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<(), Error> {
    let held: Option<(Option<DateTime<Utc>>,)> = sqlx::query_as(
        "select onboarding_completed_at from account_preference where account_id = $1",
    )
    .bind(destination)
    .fetch_optional(&mut **tx)
    .await?;

    let Some((kept,)) = held else {
        return adopt_preferences(tx, destination, source).await;
    };

    let dropped: Option<(Option<DateTime<Utc>>,)> = sqlx::query_as(
        "delete from account_preference where account_id = $1 returning onboarding_completed_at",
    )
    .bind(source)
    .fetch_optional(&mut **tx)
    .await?;

    let merged = match (kept, dropped.and_then(|(at,)| at)) {
        (Some(held_at), Some(arriving_at)) => Some(held_at.min(arriving_at)),
        (held_at, arriving_at) => held_at.or(arriving_at),
    };
    if merged == kept {
        return Ok(());
    }

    let seq = wardrobe_db::next_change_seq(tx, destination).await?;
    sqlx::query(
        "update account_preference
            set onboarding_completed_at = $2, change_seq = $3
          where account_id = $1",
    )
    .bind(destination)
    .bind(merged)
    .bind(seq)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn adopt_preferences(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    source: Uuid,
) -> Result<(), Error> {
    let moved = sqlx::query("update account_preference set account_id = $1 where account_id = $2")
        .bind(destination)
        .bind(source)
        .execute(&mut **tx)
        .await?;
    if moved.rows_affected() == 0 {
        return Ok(());
    }

    let seq = wardrobe_db::next_change_seq(tx, destination).await?;
    sqlx::query("update account_preference set change_seq = $2 where account_id = $1")
        .bind(destination)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

async fn bump_completion(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    completion: Uuid,
) -> Result<(), Error> {
    let seq = wardrobe_db::next_change_seq(tx, destination).await?;
    sqlx::query("update challenge_completion set change_seq = $2 where id = $1")
        .bind(completion)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

async fn bump_active_challenge(
    tx: &mut Transaction<'_, Postgres>,
    destination: Uuid,
    challenge: Uuid,
) -> Result<(), Error> {
    let seq = wardrobe_db::next_change_seq(tx, destination).await?;
    sqlx::query("update active_challenge set change_seq = $2 where id = $1")
        .bind(challenge)
        .bind(seq)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

async fn drain(tx: &mut Transaction<'_, Postgres>, source: Uuid) -> Result<(), Error> {
    let emptied: Vec<String> = sequenced_tables()
        .chain(std::iter::once(PREFERENCE))
        .chain(UNSEQUENCED_TABLES.iter().copied())
        .map(|table| format!("not exists (select 1 from {table} where account_id = $1)"))
        .collect();

    let gone = sqlx::query(&format!(
        "delete from account where id = $1 and {}",
        emptied.join(" and ")
    ))
    .bind(source)
    .execute(&mut **tx)
    .await?;

    if gone.rows_affected() == 1 {
        return Ok(());
    }
    tracing::error!(
        account.id = %source,
        "a merge left rows behind, so the source account was kept"
    );
    Err(Error::MergeIncomplete)
}

mod common;

use chrono::{DateTime, Duration, SubsecRound, Utc};
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_api::account::merge;
use wardrobe_api::changes::SYNCED_TABLES;
use wardrobe_api::error::Error;

use common::{Seeded, seed_every_kind};

// ------------------------------------------------------------------- fixtures

async fn account(pool: &PgPool) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(id)
}

async fn two_full_accounts(pool: &PgPool) -> sqlx::Result<(Uuid, Uuid, Seeded, Seeded)> {
    let destination = account(pool).await?;
    let held = seed_every_kind(pool, destination).await?;
    let source = account(pool).await?;
    let arriving = seed_every_kind(pool, source).await?;
    Ok((destination, source, held, arriving))
}

async fn run(pool: &PgPool, destination: Uuid, source: Uuid) -> Result<(), Error> {
    let mut tx = pool.begin().await.expect("a transaction");
    let outcome = merge::into(&mut tx, destination, source).await;
    if outcome.is_ok() {
        tx.commit().await.expect("a commit");
    }
    outcome
}

async fn positions(pool: &PgPool, account_id: Uuid) -> sqlx::Result<Vec<i64>> {
    let branches: Vec<String> = SYNCED_TABLES
        .iter()
        .map(|table| format!("select change_seq from {table} where account_id = $1"))
        .collect();
    sqlx::query_scalar(&branches.join(" union all "))
        .bind(account_id)
        .fetch_all(pool)
        .await
}

async fn rows(pool: &PgPool, table: &str, account_id: Uuid) -> sqlx::Result<i64> {
    sqlx::query_scalar(&format!(
        "select count(*) from {table} where account_id = $1"
    ))
    .bind(account_id)
    .fetch_one(pool)
    .await
}

async fn seq_of(pool: &PgPool, table: &str, id: Uuid) -> sqlx::Result<i64> {
    sqlx::query_scalar(&format!("select change_seq from {table} where id = $1"))
        .bind(id)
        .fetch_one(pool)
        .await
}

// ------------------------------------------------------------------ the cursor

#[sqlx::test(migrations = "../../migrations")]
async fn the_destination_feed_has_no_duplicate_position(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, ..) = two_full_accounts(&pool).await?;

    run(&pool, destination, source).await.expect("a merge");

    let mut seen = positions(&pool, destination).await?;
    let total = seen.len();
    seen.sort_unstable();
    seen.dedup();
    assert_eq!(
        seen.len(),
        total,
        "a duplicate position breaks the total order every pull cursor rests on"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_photo_still_precedes_its_derivative(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, ..) = two_full_accounts(&pool).await?;

    run(&pool, destination, source).await.expect("a merge");

    let pairs: Vec<(i64, i64)> = sqlx::query_as(
        "select p.change_seq, d.change_seq
           from photo_derivative d join photo p on p.id = d.photo_id
          where d.account_id = $1",
    )
    .bind(destination)
    .fetch_all(&pool)
    .await?;

    assert_eq!(pairs.len(), 2);
    for (photo, derivative) in pairs {
        assert!(
            photo < derivative,
            "a page boundary would hand the client a derivative before its photo"
        );
    }
    Ok(())
}

// -------------------------------------------------------------- the collisions

#[sqlx::test(migrations = "../../migrations")]
async fn the_earlier_completion_stays_canonical(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, held, arriving) = two_full_accounts(&pool).await?;
    sqlx::query(
        "update challenge_completion set completed_at = now() + interval '1 hour' where id = $1",
    )
    .bind(arriving.completion)
    .execute(&pool)
    .await?;

    run(&pool, destination, source).await.expect("a merge");

    let statuses: Vec<(Uuid, String)> =
        sqlx::query_as("select id, status from challenge_completion where account_id = $1")
            .bind(destination)
            .fetch_all(&pool)
            .await?;

    assert_eq!(statuses.len(), 2, "neither completion is deleted (FR-065)");
    for (id, status) in statuses {
        let expected = if id == held.completion {
            "canonical"
        } else {
            "conflicting"
        };
        assert_eq!(status, expected, "for {id}");
    }
    assert_eq!(rows(&pool, "photo", destination).await?, 2);
    let _ = arriving;
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_arriving_earlier_completion_demotes_the_one_already_here(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (destination, source, held, arriving) = two_full_accounts(&pool).await?;
    sqlx::query(
        "update challenge_completion set completed_at = now() - interval '1 hour' where id = $1",
    )
    .bind(arriving.completion)
    .execute(&pool)
    .await?;

    let before = seq_of(&pool, "challenge_completion", held.completion).await?;
    run(&pool, destination, source).await.expect("a merge");

    let status: String =
        sqlx::query_scalar("select status from challenge_completion where id = $1")
            .bind(held.completion)
            .fetch_one(&pool)
            .await?;
    assert_eq!(status, "conflicting", "§20.1: the earliest is canonical");
    assert!(
        seq_of(&pool, "challenge_completion", held.completion).await? > before,
        "a demoted row the client never sees again is a stale wear count"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_the_newest_active_challenge_survives(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, held, arriving) = two_full_accounts(&pool).await?;
    sqlx::query(
        "update active_challenge set accepted_at = now() + interval '1 hour' where id = $1",
    )
    .bind(arriving.challenge)
    .execute(&pool)
    .await?;

    let before = seq_of(&pool, "active_challenge", held.challenge).await?;
    run(&pool, destination, source).await.expect("a merge");

    let live: Vec<Uuid> = sqlx::query_scalar(
        "select id from active_challenge where account_id = $1 and deleted_at is null",
    )
    .bind(destination)
    .fetch_all(&pool)
    .await?;
    assert_eq!(live, vec![arriving.challenge]);
    assert!(
        seq_of(&pool, "active_challenge", held.challenge).await? > before,
        "the tombstone has to reach the client that is still showing it"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn similar_items_are_never_merged(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, held, arriving) = two_full_accounts(&pool).await?;
    let print: Vec<f32> = vec![41.0, 12.5, -3.25];
    for item in [held.item, arriving.item] {
        sqlx::query("update item_fingerprint set color_lab = $2 where item_id = $1")
            .bind(item)
            .bind(&print)
            .execute(&pool)
            .await?;
    }

    run(&pool, destination, source).await.expect("a merge");

    assert_eq!(
        rows(&pool, "wardrobe_item", destination).await?,
        2,
        "FR-053 keeps look-alike items separate until the user says otherwise"
    );
    assert_eq!(rows(&pool, "item_fingerprint", destination).await?, 2);
    Ok(())
}

// ------------------------------------------------------------------ what moves

#[sqlx::test(migrations = "../../migrations")]
async fn preferences_keep_the_destination_row_and_the_earliest_onboarding(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (destination, source, ..) = two_full_accounts(&pool).await?;
    let early: DateTime<Utc> = (Utc::now() - Duration::days(30)).trunc_subsecs(6);
    sqlx::query("update account_preference set onboarding_completed_at = $2 where account_id = $1")
        .bind(source)
        .bind(early)
        .execute(&pool)
        .await?;
    sqlx::query(
        "update account_preference set onboarding_completed_at = now() where account_id = $1",
    )
    .bind(destination)
    .execute(&pool)
    .await?;

    run(&pool, destination, source).await.expect("a merge");

    let kept: Option<DateTime<Utc>> = sqlx::query_scalar(
        "select onboarding_completed_at from account_preference where account_id = $1",
    )
    .bind(destination)
    .fetch_one(&pool)
    .await?;
    assert_eq!(
        kept,
        Some(early),
        "losing this sends an onboarded user back through onboarding (FR-099)"
    );
    assert_eq!(rows(&pool, "account_preference", destination).await?, 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn preferences_arrive_when_the_destination_had_none(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, ..) = two_full_accounts(&pool).await?;
    sqlx::query("delete from account_preference where account_id = $1")
        .bind(destination)
        .execute(&pool)
        .await?;

    run(&pool, destination, source).await.expect("a merge");

    assert_eq!(rows(&pool, "account_preference", destination).await?, 1);
    let mut seen = positions(&pool, destination).await?;
    let total = seen.len();
    seen.sort_unstable();
    seen.dedup();
    assert_eq!(seen.len(), total);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_tables_without_a_cursor_move_too(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, ..) = two_full_accounts(&pool).await?;
    let job = Uuid::now_v7();
    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key) values ($1, $2, 'illustration', $3)",
    )
    .bind(job)
    .bind(source)
    .bind(job.to_string())
    .execute(&pool)
    .await?;
    sqlx::query(
        "insert into ai_inference_attempt
             (id, account_id, capability, attempt_no, model, prompt_version, status)
         values ($1, $2, 'illustration', 1, 'a/model', 'v1', 'succeeded')",
    )
    .bind(Uuid::now_v7())
    .bind(source)
    .execute(&pool)
    .await?;
    sqlx::query("insert into account_device (anonymous_id, account_id) values ($1, $2)")
        .bind(Uuid::now_v7())
        .bind(source)
        .execute(&pool)
        .await?;

    run(&pool, destination, source).await.expect("a merge");

    for table in [
        "account_device",
        "ai_inference_attempt",
        "job",
        "media_object",
    ] {
        assert!(
            rows(&pool, table, destination).await? > 0,
            "{table} stayed behind and would be cascaded away with the source"
        );
    }
    for table in merge::UNSEQUENCED_TABLES {
        assert_eq!(rows(&pool, table, source).await?, 0, "{table}");
    }
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_generated_card_moves_with_the_completion_that_cites_it(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (destination, source, _, arriving) = two_full_accounts(&pool).await?;
    let card = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_card
             (id, account_id, source, title, prompt_text, locale, model, prompt_version,
              local_date, deck_index)
         values ($1, $2, 'generated', 'Seeing red', 'Wear something red', 'en', 'a/model', 'v1',
                 date '2026-08-27', 0)",
    )
    .bind(card)
    .bind(source)
    .execute(&pool)
    .await?;
    sqlx::query("update challenge_completion set card_id = $2 where id = $1")
        .bind(arriving.completion)
        .bind(card)
        .execute(&pool)
        .await?;

    run(&pool, destination, source).await.expect("a merge");

    let owner: Uuid = sqlx::query_scalar("select account_id from challenge_card where id = $1")
        .bind(card)
        .fetch_one(&pool)
        .await?;
    assert_eq!(owner, destination);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_source_account_is_gone_and_leaves_no_rows(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, ..) = two_full_accounts(&pool).await?;

    run(&pool, destination, source).await.expect("a merge");

    let left: Option<Uuid> = sqlx::query_scalar("select id from account where id = $1")
        .bind(source)
        .fetch_optional(&pool)
        .await?;
    assert_eq!(left, None);
    for table in merge::sequenced_tables().chain(merge::UNSEQUENCED_TABLES.iter().copied()) {
        assert_eq!(rows(&pool, table, source).await?, 0, "{table}");
    }
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_failed_merge_leaves_both_accounts_intact(pool: PgPool) -> sqlx::Result<()> {
    let (destination, source, ..) = two_full_accounts(&pool).await?;
    let missing = Uuid::now_v7();

    let outcome = run(&pool, missing, source).await;

    assert!(matches!(outcome, Err(Error::NotFound)));
    for table in merge::sequenced_tables() {
        assert_eq!(rows(&pool, table, source).await?, 1, "{table}");
        assert_eq!(rows(&pool, table, destination).await?, 1, "{table}");
    }
    Ok(())
}

// -------------------------------------------------------------------- the guard

#[sqlx::test(migrations = "../../migrations")]
async fn every_table_scoped_to_an_account_has_a_home_in_the_merge(
    pool: PgPool,
) -> sqlx::Result<()> {
    let scoped: Vec<String> = sqlx::query_scalar(
        "select table_name from information_schema.columns
          where table_schema = 'public' and column_name = 'account_id'",
    )
    .fetch_all(&pool)
    .await?;

    let known: Vec<&str> = merge::sequenced_tables()
        .chain(std::iter::once("account_preference"))
        .chain(merge::UNSEQUENCED_TABLES.iter().copied())
        .chain(merge::EXEMPT_TABLES.iter().copied())
        .collect();

    for table in &scoped {
        assert!(
            known.contains(&table.as_str()),
            "{table} is scoped to an account but the merge never names it, so a link \
             would cascade it away without a word"
        );
    }
    assert_eq!(scoped.len(), known.len());
    Ok(())
}

//! The product rules that live in the schema itself.
//!
//! These constraints are the enforcement for requirements the API layer must
//! never be trusted to remember: one completion per local day, one wear per
//! occurrence, immutable versions, one job per claimant. Testing them here means
//! a future handler cannot quietly regress them.

use sqlx::{PgPool, Row};
use uuid::Uuid;

// ---------------------------------------------------------------- fixtures

async fn account(pool: &PgPool) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(id)
}

async fn media(pool: &PgPool, account_id: Uuid, kind: &str) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type)
         values ($1, $2, $3, $4, 'image/png')",
    )
    .bind(id)
    .bind(account_id)
    .bind(kind)
    .bind(format!("{account_id}/{id}.png"))
    .execute(pool)
    .await?;
    Ok(id)
}

async fn photo(pool: &PgPool, account_id: Uuid) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    let object = media(pool, account_id, "original").await?;
    sqlx::query(
        "insert into photo (id, account_id, media_object_id, source, change_seq)
         values ($1, $2, $3, 'capture', 1)",
    )
    .bind(id)
    .bind(account_id)
    .bind(object)
    .execute(pool)
    .await?;
    Ok(id)
}

async fn item(pool: &PgPool, account_id: Uuid) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into wardrobe_item (id, account_id, category, change_seq)
         values ($1, $2, 'top', 1)",
    )
    .bind(id)
    .bind(account_id)
    .execute(pool)
    .await?;
    Ok(id)
}

async fn card(pool: &PgPool) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_card (id, source, prompt_text, locale)
         values ($1, 'curated', 'Wear something blue', 'en')",
    )
    .bind(id)
    .execute(pool)
    .await?;
    Ok(id)
}

async fn complete(
    pool: &PgPool,
    account_id: Uuid,
    card_id: Uuid,
    day: &str,
    status: &str,
) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into challenge_completion
             (id, account_id, card_id, local_date, time_zone, completed_at, status, change_seq)
         values ($1, $2, $3, $4::date, 'Asia/Jakarta', now(), $5, 1)",
    )
    .bind(id)
    .bind(account_id)
    .bind(card_id)
    .bind(day)
    .bind(status)
    .execute(pool)
    .await?;
    Ok(id)
}

// ----------------------------------------------------------- daily identity

/// FR-065: one canonical completion per account per user-local day.
#[sqlx::test(migrations = "../../migrations")]
async fn a_second_canonical_completion_on_the_same_local_day_is_rejected(
    pool: PgPool,
) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let card_id = card(&pool).await?;
    complete(&pool, account_id, card_id, "2026-08-15", "canonical").await?;

    let second = complete(&pool, account_id, card_id, "2026-08-15", "canonical").await;

    assert!(second.is_err(), "the partial unique index did not hold");
    Ok(())
}

/// The losing completion is preserved rather than refused — the user still owns
/// that photo and must be able to choose (FR-065).
#[sqlx::test(migrations = "../../migrations")]
async fn a_conflicting_completion_may_share_the_day(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let card_id = card(&pool).await?;
    complete(&pool, account_id, card_id, "2026-08-15", "canonical").await?;

    complete(&pool, account_id, card_id, "2026-08-15", "conflicting").await?;

    let count: i64 = sqlx::query_scalar(
        "select count(*) from challenge_completion where account_id = $1 and local_date = $2::date",
    )
    .bind(account_id)
    .bind("2026-08-15")
    .fetch_one(&pool)
    .await?;
    assert_eq!(count, 2);
    Ok(())
}

/// Two different people completing the same calendar day must not collide.
#[sqlx::test(migrations = "../../migrations")]
async fn the_daily_limit_is_per_account(pool: PgPool) -> sqlx::Result<()> {
    let card_id = card(&pool).await?;
    let first = account(&pool).await?;
    let second = account(&pool).await?;

    complete(&pool, first, card_id, "2026-08-15", "canonical").await?;
    complete(&pool, second, card_id, "2026-08-15", "canonical").await?;
    Ok(())
}

// ------------------------------------------------------------------- wears

/// FR-064: a correction revises the wear for that occurrence, never adds one.
#[sqlx::test(migrations = "../../migrations")]
async fn the_same_occurrence_upserts_into_one_wear(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;
    let photo_id = photo(&pool, account_id).await?;

    for _ in 0..2 {
        sqlx::query(
            "insert into wear_record
                 (id, account_id, item_id, source_photo_id, worn_on, change_seq)
             values ($1, $2, $3, $4, current_date, 1)
             on conflict (account_id, item_id, source_photo_id) do update
                 set revision   = wear_record.revision + 1,
                     updated_at = now()",
        )
        .bind(Uuid::now_v7())
        .bind(account_id)
        .bind(item_id)
        .bind(photo_id)
        .execute(&pool)
        .await?;
    }

    let row = sqlx::query("select count(*) as total, max(revision) as revision from wear_record")
        .fetch_one(&pool)
        .await?;
    assert_eq!(row.get::<i64, _>("total"), 1);
    assert_eq!(row.get::<i32, _>("revision"), 2);
    Ok(())
}

/// A wear with no source photo is a manual entry, and those are legitimately
/// repeatable — which is exactly why the unique key is allowed many nulls.
#[sqlx::test(migrations = "../../migrations")]
async fn manual_wears_without_a_source_photo_may_repeat(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;

    for _ in 0..2 {
        sqlx::query(
            "insert into wear_record (id, account_id, item_id, worn_on, change_seq)
             values ($1, $2, $3, current_date, 1)",
        )
        .bind(Uuid::now_v7())
        .bind(account_id)
        .bind(item_id)
        .execute(&pool)
        .await?;
    }

    let total: i64 = sqlx::query_scalar("select count(*) from wear_record")
        .fetch_one(&pool)
        .await?;
    assert_eq!(total, 2);
    Ok(())
}

// -------------------------------------------------------- immutable versions

/// FR-063: set union by id. Re-sending a fingerprint must never rewrite the
/// stored one, or an old source would silently change meaning.
#[sqlx::test(migrations = "../../migrations")]
async fn re_sending_a_fingerprint_never_overwrites_it(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;
    let fingerprint_id = Uuid::now_v7();

    for quality in [1.0_f32, 0.2_f32] {
        sqlx::query(
            "insert into item_fingerprint
                 (id, account_id, item_id, version, color_lab, aspect_ratio,
                  feature_print, mask_quality, change_seq)
             values ($1, $2, $3, 'v1', array[70.0, 5.0, 15.0]::real[], 0.8, '\\x00'::bytea, $4, 1)
             on conflict (id) do nothing",
        )
        .bind(fingerprint_id)
        .bind(account_id)
        .bind(item_id)
        .bind(quality)
        .execute(&pool)
        .await?;
    }

    let quality: f32 =
        sqlx::query_scalar("select mask_quality from item_fingerprint where id = $1")
            .bind(fingerprint_id)
            .fetch_one(&pool)
            .await?;
    assert!(
        (quality - 1.0).abs() < f32::EPSILON,
        "the first value was lost"
    );
    Ok(())
}

// ------------------------------------------------------------ change feed

/// The cursor's whole promise: a total order per account with no repeats.
#[sqlx::test(migrations = "../../migrations")]
async fn change_seq_increases_monotonically_per_account(pool: PgPool) -> sqlx::Result<()> {
    let first = account(&pool).await?;
    let second = account(&pool).await?;
    let mut conn = pool.acquire().await?;

    let mut seen = Vec::new();
    for _ in 0..3 {
        seen.push(wardrobe_db::next_change_seq(&mut conn, first).await?);
    }
    let other = wardrobe_db::next_change_seq(&mut conn, second).await?;

    assert_eq!(seen, vec![1, 2, 3]);
    assert_eq!(other, 1, "accounts must not share a counter");
    Ok(())
}

// -------------------------------------------------------------------- jobs

/// One job per new item, so a retried enqueue cannot buy a second render.
#[sqlx::test(migrations = "../../migrations")]
async fn the_same_job_cannot_be_enqueued_twice(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;
    let insert =
        "insert into job (id, account_id, kind, dedupe_key) values ($1, $2, 'illustration', $3)";

    sqlx::query(insert)
        .bind(Uuid::now_v7())
        .bind(account_id)
        .bind(item_id.to_string())
        .execute(&pool)
        .await?;
    let second = sqlx::query(insert)
        .bind(Uuid::now_v7())
        .bind(account_id)
        .bind(item_id.to_string())
        .execute(&pool)
        .await;

    assert!(second.is_err());
    Ok(())
}

/// `skip locked` is the reason two workers can share one table without a broker.
#[sqlx::test(migrations = "../../migrations")]
async fn two_claimants_never_receive_the_same_job(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    sqlx::query(
        "insert into job (id, account_id, kind, dedupe_key) values ($1, $2, 'illustration', 'a')",
    )
    .bind(Uuid::now_v7())
    .bind(account_id)
    .execute(&pool)
    .await?;

    let mut first = pool.begin().await?;
    let mut second = pool.begin().await?;

    let claimed = wardrobe_db::claim_job(&mut first, "illustration").await?;
    let stolen = wardrobe_db::claim_job(&mut second, "illustration").await?;

    assert!(claimed.is_some());
    assert!(stolen.is_none(), "the second worker took a locked job");
    first.commit().await?;
    second.rollback().await?;
    Ok(())
}

// ---------------------------------------------------------------------- ai

/// FR-082: a provider whose terms permit training on submitted content is not
/// merely discouraged — it cannot be stored as approved.
#[sqlx::test(migrations = "../../migrations")]
async fn a_training_permitting_provider_cannot_be_allowlisted(pool: PgPool) -> sqlx::Result<()> {
    let insert = "insert into ai_provider_allowlist
                      (provider_slug, forbids_training, retention_policy, approved_by)
                  values ($1, $2, 'zero', 'tests')";

    sqlx::query(insert)
        .bind("good-provider")
        .bind(true)
        .execute(&pool)
        .await?;
    let rejected = sqlx::query(insert)
        .bind("trains-on-your-data")
        .bind(false)
        .execute(&pool)
        .await;

    assert!(rejected.is_err());
    Ok(())
}

/// FR-072: the primary key is what makes "one active configuration per
/// capability" true, rather than a convention a handler could break.
#[sqlx::test(migrations = "../../migrations")]
async fn a_capability_has_exactly_one_configuration(pool: PgPool) -> sqlx::Result<()> {
    let insert = "insert into ai_model_config
                      (capability, model_class, active_model, prompt_version, updated_by)
                  values ('challenge_text', 'text', $1, 'v1', 'tests')";

    sqlx::query(insert).bind("model-a").execute(&pool).await?;
    let second = sqlx::query(insert).bind("model-b").execute(&pool).await;

    assert!(second.is_err());
    Ok(())
}

/// The illustration capability must never be pointed at a text model.
#[sqlx::test(migrations = "../../migrations")]
async fn the_illustration_capability_must_use_an_image_model(pool: PgPool) -> sqlx::Result<()> {
    let mismatched = sqlx::query(
        "insert into ai_model_config
             (capability, model_class, active_model, prompt_version, updated_by)
         values ('illustration', 'text', 'some-text-model', 'v1', 'tests')",
    )
    .execute(&pool)
    .await;

    assert!(mismatched.is_err());
    Ok(())
}

// ---------------------------------------------------------------- deletion

/// FR-071: deleting the account removes its rows, and the media objects it owned
/// must still be enumerable beforehand so the storage cleanup has a work list.
#[sqlx::test(migrations = "../../migrations")]
async fn deleting_an_account_cascades_and_its_objects_were_enumerable(
    pool: PgPool,
) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;
    photo(&pool, account_id).await?;
    let cutout = media(&pool, account_id, "cutout").await?;
    sqlx::query(
        "insert into item_cutout (id, account_id, item_id, media_object_id, change_seq)
         values ($1, $2, $3, $4, 1)",
    )
    .bind(Uuid::now_v7())
    .bind(account_id)
    .bind(item_id)
    .bind(cutout)
    .execute(&pool)
    .await?;

    let keys: Vec<String> =
        sqlx::query_scalar("select storage_key from media_object where account_id = $1")
            .bind(account_id)
            .fetch_all(&pool)
            .await?;
    sqlx::query("delete from account where id = $1")
        .bind(account_id)
        .execute(&pool)
        .await?;

    assert_eq!(keys.len(), 2, "both objects must reach the cleanup list");
    let remaining: i64 = sqlx::query_scalar("select count(*) from wardrobe_item")
        .fetch_one(&pool)
        .await?;
    assert_eq!(remaining, 0);
    Ok(())
}

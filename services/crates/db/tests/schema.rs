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

// ------------------------------------------------------------ value bounds

#[sqlx::test(migrations = "../../migrations")]
async fn a_fingerprint_must_carry_three_lab_components(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;

    let rejected = sqlx::query(
        "insert into item_fingerprint
             (id, account_id, item_id, version, color_lab, aspect_ratio, feature_print,
              mask_quality, change_seq)
         values ($1, $2, $3, 'v1', $4, 0.75, '\\x00'::bytea, 0.9, 1)",
    )
    .bind(Uuid::now_v7())
    .bind(account_id)
    .bind(item_id)
    .bind(vec![72.5_f32, -3.25])
    .execute(&pool)
    .await;

    assert!(rejected.is_err(), "two components is not a Lab colour");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn updated_at_advances_without_the_caller_setting_it(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;

    let before: chrono::DateTime<chrono::Utc> =
        sqlx::query_scalar("select updated_at from wardrobe_item where id = $1")
            .bind(item_id)
            .fetch_one(&pool)
            .await?;
    sqlx::query("update wardrobe_item set name = 'Kemeja' where id = $1")
        .bind(item_id)
        .execute(&pool)
        .await?;
    let after: chrono::DateTime<chrono::Utc> =
        sqlx::query_scalar("select updated_at from wardrobe_item where id = $1")
            .bind(item_id)
            .fetch_one(&pool)
            .await?;

    assert_ne!(
        after, before,
        "the trigger must refresh updated_at; monotonicity is the clock's promise, not its"
    );
    Ok(())
}

// -------------------------------------------------------- canvas documents

async fn derivative(pool: &PgPool, account_id: Uuid, photo_id: Uuid) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    let object = media(pool, account_id, "derivative").await?;
    sqlx::query(
        "insert into photo_derivative (id, account_id, photo_id, media_object_id, change_seq)
         values ($1, $2, $3, $4, 1)",
    )
    .bind(id)
    .bind(account_id)
    .bind(photo_id)
    .bind(object)
    .execute(pool)
    .await?;
    Ok(id)
}

async fn document(
    pool: &PgPool,
    account_id: Uuid,
    completion_id: Uuid,
    derivative_id: Uuid,
) -> sqlx::Result<sqlx::postgres::PgQueryResult> {
    let object = media(pool, account_id, "document").await?;
    sqlx::query(
        "insert into canvas_document
             (id, account_id, completion_id, derivative_id, schema_version, media_object_id,
              change_seq)
         values ($1, $2, $3, $4, 2, $5, 1)",
    )
    .bind(Uuid::now_v7())
    .bind(account_id)
    .bind(completion_id)
    .bind(derivative_id)
    .bind(object)
    .execute(pool)
    .await
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_derivative_has_exactly_one_document(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let card_id = card(&pool).await?;
    let photo_id = photo(&pool, account_id).await?;
    let completion_id = complete(&pool, account_id, card_id, "2026-08-20", "canonical").await?;
    let derivative_id = derivative(&pool, account_id, photo_id).await?;

    document(&pool, account_id, completion_id, derivative_id).await?;
    let second = document(&pool, account_id, completion_id, derivative_id).await;

    assert!(second.is_err(), "a second document must not claim the pair");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_document_is_usable_without_its_undo_history(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let card_id = card(&pool).await?;
    let photo_id = photo(&pool, account_id).await?;
    let completion_id = complete(&pool, account_id, card_id, "2026-08-20", "canonical").await?;
    let derivative_id = derivative(&pool, account_id, photo_id).await?;

    document(&pool, account_id, completion_id, derivative_id).await?;

    let stored: i64 = sqlx::query_scalar(
        "select count(*) from canvas_document where history_media_object_id is null",
    )
    .fetch_one(&pool)
    .await?;
    assert_eq!(stored, 1);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_completion_has_one_primary_photo_and_any_number_of_layers(
    pool: PgPool,
) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let card_id = card(&pool).await?;
    let completion_id = complete(&pool, account_id, card_id, "2026-08-20", "canonical").await?;

    for (photo_id, role) in [
        (photo(&pool, account_id).await?, "primary"),
        (photo(&pool, account_id).await?, "layer"),
        (photo(&pool, account_id).await?, "layer"),
    ] {
        sqlx::query(
            "insert into completion_photo (completion_id, photo_id, role) values ($1, $2, $3)",
        )
        .bind(completion_id)
        .bind(photo_id)
        .bind(role)
        .execute(&pool)
        .await?;
    }

    let extra_primary = sqlx::query(
        "insert into completion_photo (completion_id, photo_id, role) values ($1, $2, 'primary')",
    )
    .bind(completion_id)
    .bind(photo(&pool, account_id).await?)
    .execute(&pool)
    .await;

    assert!(extra_primary.is_err(), "only one photo can be primary");
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn deleting_a_completion_takes_its_documents_and_photo_links(
    pool: PgPool,
) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let card_id = card(&pool).await?;
    let photo_id = photo(&pool, account_id).await?;
    let completion_id = complete(&pool, account_id, card_id, "2026-08-20", "canonical").await?;
    let derivative_id = derivative(&pool, account_id, photo_id).await?;
    document(&pool, account_id, completion_id, derivative_id).await?;
    sqlx::query(
        "insert into completion_photo (completion_id, photo_id, role) values ($1, $2, 'primary')",
    )
    .bind(completion_id)
    .bind(photo_id)
    .execute(&pool)
    .await?;

    let keys: Vec<String> = sqlx::query_scalar(
        "select storage_key from media_object where account_id = $1 and kind = 'document'",
    )
    .bind(account_id)
    .fetch_all(&pool)
    .await?;
    sqlx::query("delete from challenge_completion where id = $1")
        .bind(completion_id)
        .execute(&pool)
        .await?;

    assert_eq!(
        keys.len(),
        1,
        "the document object must reach the cleanup list"
    );
    let documents: i64 = sqlx::query_scalar("select count(*) from canvas_document")
        .fetch_one(&pool)
        .await?;
    let links: i64 = sqlx::query_scalar("select count(*) from completion_photo")
        .fetch_one(&pool)
        .await?;
    assert_eq!((documents, links), (0, 0));
    Ok(())
}

// -------------------------------------------------------------- session

async fn session(pool: &PgPool, account_id: Uuid, family_id: Uuid, n: u8) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        "insert into session (id, account_id, family_id, token_hash, refresh_token_hash, expires_at)
         values ($1, $2, $3, $4, $5, now() + interval '30 days')",
    )
    .bind(id)
    .bind(account_id)
    .bind(family_id)
    .bind(vec![n])
    .bind(vec![100 + n])
    .execute(pool)
    .await?;
    Ok(id)
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_refresh_token_belongs_to_one_session(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let family_id = Uuid::now_v7();
    session(&pool, account_id, family_id, 1).await?;

    let duplicate = sqlx::query(
        "insert into session (id, account_id, family_id, token_hash, refresh_token_hash, expires_at)
         values ($1, $2, $3, $4, $5, now() + interval '30 days')",
    )
    .bind(Uuid::now_v7())
    .bind(account_id)
    .bind(family_id)
    .bind(vec![9_u8])
    .bind(vec![101_u8])
    .execute(&pool)
    .await;

    assert!(duplicate.is_err());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn revoking_a_family_revokes_every_session_in_it(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let family_id = Uuid::now_v7();
    let other_family = Uuid::now_v7();
    session(&pool, account_id, family_id, 1).await?;
    session(&pool, account_id, family_id, 2).await?;
    session(&pool, account_id, other_family, 3).await?;

    sqlx::query("update session set revoked_at = now() where family_id = $1")
        .bind(family_id)
        .execute(&pool)
        .await?;

    let live: i64 = sqlx::query_scalar("select count(*) from session where revoked_at is null")
        .fetch_one(&pool)
        .await?;
    assert_eq!(live, 1, "the unrelated device keeps its session");
    Ok(())
}

// ---------------------------------------------------------- preferences

#[sqlx::test(migrations = "../../migrations")]
async fn recent_stickers_are_capped_and_follow_the_account(pool: PgPool) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let twelve: Vec<String> = (0..12).map(|n| format!("sticker.{n}")).collect();

    sqlx::query(
        "insert into account_preference (account_id, recent_sticker_ids, change_seq)
         values ($1, $2, 1)",
    )
    .bind(account_id)
    .bind(&twelve)
    .execute(&pool)
    .await?;

    let thirteen: Vec<String> = (0..13).map(|n| format!("sticker.{n}")).collect();
    let rejected =
        sqlx::query("update account_preference set recent_sticker_ids = $2 where account_id = $1")
            .bind(account_id)
            .bind(&thirteen)
            .execute(&pool)
            .await;
    assert!(rejected.is_err(), "the thirteenth sticker must not fit");

    sqlx::query("delete from account where id = $1")
        .bind(account_id)
        .execute(&pool)
        .await?;
    let remaining: i64 = sqlx::query_scalar("select count(*) from account_preference")
        .fetch_one(&pool)
        .await?;
    assert_eq!(remaining, 0, "preferences are deleted with the account");
    Ok(())
}

// ------------------------------------------------------------ error facts

#[sqlx::test(migrations = "../../migrations")]
async fn a_database_error_yields_a_constraint_name_and_no_row_content(
    pool: PgPool,
) -> sqlx::Result<()> {
    let account_id = account(&pool).await?;
    let item_id = item(&pool, account_id).await?;
    sqlx::query("update wardrobe_item set name = 'Kemeja linen biru' where id = $1")
        .bind(item_id)
        .execute(&pool)
        .await?;

    let rejected =
        sqlx::query("update wardrobe_item set description = repeat('x', 501) where id = $1")
            .bind(item_id)
            .execute(&pool)
            .await
            .expect_err("the length check must reject it");
    let facts = wardrobe_db::error_facts(&rejected);

    assert_eq!(facts.code, "database");
    assert_eq!(facts.sqlstate.as_deref(), Some("23514"));
    assert_eq!(
        facts.constraint.as_deref(),
        Some("wardrobe_item_description_check")
    );
    let recorded = format!(
        "{facts:?}",
        facts = (facts.code, &facts.sqlstate, &facts.constraint)
    );
    assert!(
        !recorded.contains("Kemeja"),
        "nothing derived from the error may carry a row value"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_missing_row_is_classified_without_touching_the_database_variant(
    pool: PgPool,
) -> sqlx::Result<()> {
    let missing = sqlx::query_scalar::<_, i64>("select change_seq from account where id = $1")
        .bind(Uuid::now_v7())
        .fetch_one(&pool)
        .await
        .expect_err("no such account");
    let facts = wardrobe_db::error_facts(&missing);

    assert_eq!(facts.code, "row_not_found");
    assert!(facts.sqlstate.is_none() && facts.constraint.is_none());
    Ok(())
}

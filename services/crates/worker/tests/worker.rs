use chrono::Duration;
use sqlx::PgPool;
use uuid::Uuid;
use wardrobe_storage::{Settings, Storage};
use wardrobe_worker::{Outcome, SWEEP_MEDIA, Swept, enqueue_sweep, run_one, sweep_media};

// ------------------------------------------------------------------- fixtures

fn store() -> Storage {
    fn env(name: &str, fallback: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| fallback.to_owned())
    }
    Storage::new(&Settings {
        endpoint: env("TEST_S3_ENDPOINT", "http://localhost:9100"),
        region: env("TEST_S3_REGION", "us-east-1"),
        bucket: env("TEST_S3_BUCKET", "wardrobe"),
        access_key_id: env("TEST_S3_ACCESS_KEY_ID", "wardrobe"),
        secret_access_key: env("TEST_S3_SECRET_ACCESS_KEY", "wardrobe-dev-secret"),
        path_style: true,
        presign_ttl: std::time::Duration::from_secs(300),
    })
}

async fn queue_state(pool: &PgPool) -> String {
    let database: String = sqlx::query_scalar("select current_database()")
        .fetch_one(pool)
        .await
        .unwrap_or_else(|error| format!("<{error}>"));
    let rows: Vec<(Uuid, String, String, i32, bool)> = sqlx::query_as(
        "select id, kind, status, attempts, run_after <= now() from job order by run_after",
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();
    format!("database {database}, {} job row(s): {rows:?}", rows.len())
}

async fn account(pool: &PgPool) -> sqlx::Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query("insert into account (id) values ($1)")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(id)
}

async fn a_job(pool: &PgPool, kind: &str, max_attempts: i32) -> sqlx::Result<Uuid> {
    let existing: i64 = sqlx::query_scalar("select count(*) from job")
        .fetch_one(pool)
        .await?;
    assert_eq!(
        existing,
        0,
        "a test database was handed over dirty: {}",
        queue_state(pool).await
    );

    let id = Uuid::now_v7();
    sqlx::query(
        "insert into job (id, kind, dedupe_key, max_attempts, run_after)
         values ($1, $2, $1::text, $3, now() - interval '1 minute')",
    )
    .bind(id)
    .bind(kind)
    .bind(max_attempts)
    .execute(pool)
    .await?;
    Ok(id)
}

async fn state(pool: &PgPool, id: Uuid) -> (String, i32, Option<String>) {
    sqlx::query_as("select status, attempts, last_error_code from job where id = $1")
        .bind(id)
        .fetch_one(pool)
        .await
        .expect("the job row")
}

async fn make_claimable(pool: &PgPool, id: Uuid) {
    sqlx::query("update job set run_after = now() - interval '1 minute' where id = $1")
        .bind(id)
        .execute(pool)
        .await
        .expect("update");
}

/// A media row old enough to sweep, optionally with its bytes already in the store.
async fn reserved(pool: &PgPool, uploaded: bool, age: Duration) -> sqlx::Result<(Uuid, String)> {
    let owner = account(pool).await?;
    let id = Uuid::now_v7();
    let key = format!("{owner}/original/{id}");
    if uploaded {
        store()
            .put(&key, b"real bytes".to_vec(), "image/jpeg")
            .await
            .expect("the object lands");
    }
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type, created_at)
         values ($1, $2, 'original', $3, 'image/jpeg', now() - $4::interval)",
    )
    .bind(id)
    .bind(owner)
    .bind(&key)
    .bind(age)
    .execute(pool)
    .await?;
    Ok((id, key))
}

const GRACE: Duration = Duration::hours(24);

// ------------------------------------------------------------------ retrying

#[sqlx::test(migrations = "../../migrations")]
async fn a_failing_job_retries_to_its_limit_then_stops(pool: PgPool) -> sqlx::Result<()> {
    let id = a_job(&pool, "probe", 2).await?;

    let first = run_one(&pool, "probe", |_| async { Err("handler_refused") }).await?;
    assert_eq!(
        first,
        Some(Outcome::Retrying),
        "{}",
        queue_state(&pool).await
    );
    assert_eq!(
        state(&pool, id).await.0,
        "pending",
        "{}",
        queue_state(&pool).await
    );

    make_claimable(&pool, id).await;
    let second = run_one(&pool, "probe", |_| async { Err("handler_refused") }).await?;
    assert_eq!(
        second,
        Some(Outcome::Failed),
        "{}",
        queue_state(&pool).await
    );

    let (status, attempts, code) = state(&pool, id).await;
    assert_eq!((status.as_str(), attempts), ("failed", 2));
    assert_eq!(code.as_deref(), Some("handler_refused"));

    make_claimable(&pool, id).await;
    assert_eq!(
        run_one(&pool, "probe", |_| async { Ok(()) }).await?,
        None,
        "a job past its attempts must stay stopped, not creep back into the queue"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_job_whose_worker_never_came_back_can_be_claimed_again(pool: PgPool) -> sqlx::Result<()> {
    let id = a_job(&pool, "probe", 3).await?;
    sqlx::query(
        "update job set status = 'running', started_at = now() - interval '1 hour' where id = $1",
    )
    .bind(id)
    .execute(&pool)
    .await?;

    assert_eq!(
        run_one(&pool, "probe", |_| async { Ok(()) }).await?,
        None,
        "a stalled job is invisible until something reclaims it"
    );

    let mut conn = pool.acquire().await?;
    let reclaimed = wardrobe_db::reclaim_stalled(&mut conn, "probe", Duration::minutes(15)).await?;
    drop(conn);
    assert_eq!(reclaimed, 1, "{}", queue_state(&pool).await);

    assert_eq!(
        run_one(&pool, "probe", |_| async { Ok(()) }).await?,
        Some(Outcome::Succeeded),
        "{}: {}",
        "a killed worker must not strand its job forever",
        queue_state(&pool).await
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_succeeding_job_clears_the_error_it_recorded_earlier(pool: PgPool) -> sqlx::Result<()> {
    let id = a_job(&pool, "probe", 3).await?;

    run_one(&pool, "probe", |_| async { Err("temporary") }).await?;
    assert_eq!(
        state(&pool, id).await.2.as_deref(),
        Some("temporary"),
        "{}",
        queue_state(&pool).await
    );

    make_claimable(&pool, id).await;
    run_one(&pool, "probe", |_| async { Ok(()) }).await?;

    let (status, _, code) = state(&pool, id).await;
    assert_eq!(status, "succeeded", "{}", queue_state(&pool).await);
    assert_eq!(
        code, None,
        "a stale error code reads as a failure that is not there"
    );
    Ok(())
}

// ------------------------------------------------------------------ enqueuing

#[sqlx::test(migrations = "../../migrations")]
async fn enqueuing_twice_in_the_same_hour_makes_one_job(pool: PgPool) -> sqlx::Result<()> {
    let now = chrono::Utc::now();
    assert!(enqueue_sweep(&pool, now).await?);
    assert!(
        !enqueue_sweep(&pool, now).await?,
        "two workers ticking together must not sweep twice"
    );

    let jobs: i64 = sqlx::query_scalar("select count(*) from job where kind = $1")
        .bind(SWEEP_MEDIA)
        .fetch_one(&pool)
        .await?;
    assert_eq!(jobs, 1);

    assert!(enqueue_sweep(&pool, now + Duration::hours(1)).await?);
    Ok(())
}

// ------------------------------------------------------------------- sweeping

#[sqlx::test(migrations = "../../migrations")]
async fn the_sweep_removes_a_row_whose_bytes_never_arrived(pool: PgPool) -> sqlx::Result<()> {
    let (id, _) = reserved(&pool, false, Duration::hours(48)).await?;

    let swept = sweep_media(&pool, &store(), GRACE).await.expect("sweep");
    assert_eq!(
        swept,
        Swept {
            removed: 1,
            stamped: 0
        }
    );

    let left: i64 = sqlx::query_scalar("select count(*) from media_object where id = $1")
        .bind(id)
        .fetch_one(&pool)
        .await?;
    assert_eq!(left, 0);
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_sweep_stamps_instead_of_deleting_when_the_bytes_did_arrive(
    pool: PgPool,
) -> sqlx::Result<()> {
    let (id, key) = reserved(&pool, true, Duration::hours(48)).await?;

    let swept = sweep_media(&pool, &store(), GRACE).await.expect("sweep");
    assert_eq!(
        swept,
        Swept {
            removed: 0,
            stamped: 1
        }
    );

    let stamped: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("select uploaded_at from media_object where id = $1")
            .bind(id)
            .fetch_one(&pool)
            .await?;
    assert!(
        stamped.is_some(),
        "uploaded_at is only set on first download, so a client that uploaded and never fetched \
         would otherwise have its object orphaned by the very job meant to tidy up"
    );
    assert!(store().head(&key).await.expect("head").is_some());
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_row_still_inside_the_grace_period_is_left_alone(pool: PgPool) -> sqlx::Result<()> {
    reserved(&pool, false, Duration::hours(1)).await?;

    assert_eq!(
        sweep_media(&pool, &store(), GRACE).await.expect("sweep"),
        Swept::default(),
        "sweeping an upload still in flight breaks a client that is working correctly"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_media_row_something_still_points_at_is_never_swept(pool: PgPool) -> sqlx::Result<()> {
    let (id, _) = reserved(&pool, false, Duration::hours(48)).await?;
    let owner: Uuid = sqlx::query_scalar("select account_id from media_object where id = $1")
        .bind(id)
        .fetch_one(&pool)
        .await?;
    sqlx::query(
        "insert into photo (id, account_id, media_object_id, source, change_seq)
         values ($1, $2, $3, 'capture', 1)",
    )
    .bind(Uuid::now_v7())
    .bind(owner)
    .bind(id)
    .execute(&pool)
    .await?;

    assert_eq!(
        sweep_media(&pool, &store(), GRACE).await.expect("sweep"),
        Swept::default(),
        "photo.media_object_id restricts deletion, so sweeping a referenced row would fail the job"
    );
    Ok(())
}

// -------------------------------------------------------- kinds not yet handled

#[sqlx::test(migrations = "../../migrations")]
async fn an_illustration_job_waits_because_no_registered_kind_claims_it(
    pool: PgPool,
) -> sqlx::Result<()> {
    let owner = account(&pool).await?;
    let id = Uuid::now_v7();
    sqlx::query("insert into job (id, account_id, kind, dedupe_key) values ($1, $2, $3, $1::text)")
        .bind(id)
        .bind(owner)
        .bind(wardrobe_db::ILLUSTRATION)
        .execute(&pool)
        .await?;

    for kind in wardrobe_worker::kinds(false, false, false) {
        assert_eq!(
            run_one(&pool, kind, |_| async { Ok(()) }).await?,
            None,
            "{kind} must not reach across into work it does not know how to do"
        );
    }

    let (status, attempts, _) = state(&pool, id).await;
    assert_eq!(
        (status.as_str(), attempts),
        ("pending", 0),
        "claiming a job with no handler would mark it failed three times before T15b even exists"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_styling_job_waits_until_an_object_store_is_configured(pool: PgPool) -> sqlx::Result<()> {
    let owner = account(&pool).await?;
    let id = Uuid::now_v7();
    sqlx::query("insert into job (id, account_id, kind, dedupe_key) values ($1, $2, $3, $1::text)")
        .bind(id)
        .bind(owner)
        .bind(wardrobe_db::STYLISE_ILLUSTRATION)
        .execute(&pool)
        .await?;

    for kind in wardrobe_worker::kinds(true, false, false) {
        assert_eq!(run_one(&pool, kind, |_| async { Ok(()) }).await?, None);
    }
    assert_eq!(
        state(&pool, id).await.0,
        "pending",
        "with nowhere to read the generation from, the job waits rather than failing"
    );

    for kind in wardrobe_worker::kinds(true, true, true) {
        run_one(&pool, kind, |_| async { Ok(()) }).await?;
    }
    assert_eq!(
        state(&pool, id).await.0,
        "succeeded",
        "and a configured store is what lets the sticker treatment claim it"
    );
    Ok(())
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_sweeper_discards_an_upload_over_its_cap_instead_of_stamping_it(
    pool: PgPool,
) -> sqlx::Result<()> {
    let owner = account(&pool).await?;
    let media = Uuid::now_v7();
    let key = format!("{owner}/cutout/{media}");
    let cap = usize::try_from(wardrobe_db::upload_cap("cutout")).expect("a positive cap");
    store()
        .put(&key, vec![0u8; cap + 1], "image/png")
        .await
        .expect("the oversize object lands");
    sqlx::query(
        "insert into media_object (id, account_id, kind, storage_key, content_type, created_at)
         values ($1, $2, 'cutout', $3, 'image/png', now() - interval '48 hours')",
    )
    .bind(media)
    .bind(owner)
    .bind(&key)
    .execute(&pool)
    .await?;

    let swept = sweep_media(&pool, &store(), Duration::hours(24))
        .await
        .expect("the sweep runs");

    assert_eq!(swept.stamped, 0, "an oversize upload must never be stamped");
    let left: i64 = sqlx::query_scalar("select count(*) from media_object where id = $1")
        .bind(media)
        .fetch_one(&pool)
        .await?;
    assert_eq!(left, 0);
    Ok(())
}

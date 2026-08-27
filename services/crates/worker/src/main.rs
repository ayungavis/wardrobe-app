use std::process::ExitCode;
use std::time::Duration as Wait;

use chrono::{Duration, Utc};
use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use wardrobe_db::ClaimedJob;
use wardrobe_storage::Storage;
use wardrobe_worker::challenge;
use wardrobe_worker::illustration::{self, Provider};
use wardrobe_worker::inference;
use wardrobe_worker::template;
use wardrobe_worker::{SWEEP_GRACE_HOURS, SWEEP_MEDIA, kinds};

fn main() -> ExitCode {
    let Ok(database_url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL is required");
        return ExitCode::FAILURE;
    };

    let _sentry_guard_outliving_the_runtime =
        wardrobe_observability::init(&wardrobe_observability::Settings::from_env());

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer())
        .with(sentry::integrations::tracing::layer())
        .init();

    serve(database_url)
}

#[tokio::main]
async fn serve(database_url: String) -> ExitCode {
    match run(database_url).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            tracing::error!("{error}");
            ExitCode::FAILURE
        }
    }
}

async fn run(database_url: String) -> Result<(), Box<dyn std::error::Error>> {
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;
    let storage = verified_storage().await?;
    let provider = provider_from_env();
    let interval = Wait::from_secs(poll_seconds());
    tracing::info!(poll_seconds = interval.as_secs(), "worker started");

    let mut stopping = std::pin::pin!(sigterm_or_ctrl_c());
    let mut announced = None;
    loop {
        let readiness = tick(&pool, storage.as_ref(), provider.as_ref()).await;
        if announced != Some(readiness) {
            announce(readiness, storage.is_some(), provider.is_some());
            announced = Some(readiness);
        }
        tokio::select! {
            () = &mut stopping => break,
            () = tokio::time::sleep(interval) => {}
        }
    }

    tracing::info!("shutting down after finishing the job in hand");
    Ok(())
}

async fn verified_storage() -> Result<Option<Storage>, Box<dyn std::error::Error>> {
    let Some(settings) = wardrobe_storage::Settings::from_env() else {
        tracing::warn!("no object store configured; storage-backed kinds will wait");
        return Ok(None);
    };

    let storage = Storage::new(&settings);
    storage.ensure_bucket().await.map_err(|error| {
        format!(
            "object store unreachable: bucket {:?} at {:?} ({error}). \
             A path-style endpoint must not repeat the bucket name.",
            settings.bucket, settings.endpoint
        )
    })?;
    tracing::info!(bucket = %settings.bucket, "object store reachable");
    Ok(Some(storage))
}

fn provider_from_env() -> Option<Provider> {
    let api_key = std::env::var("OPENROUTER_API_KEY")
        .ok()
        .filter(|key| !key.is_empty())?;

    let client = reqwest::Client::builder()
        .timeout(Wait::from_secs(wardrobe_worker::PROVIDER_TIMEOUT_SECONDS))
        .build()
        .ok()?;

    Some(Provider {
        client,
        base_url: std::env::var("OPENROUTER_BASE_URL")
            .unwrap_or_else(|_| illustration::openrouter::DEFAULT_BASE_URL.to_owned()),
        api_key,
    })
}

fn poll_seconds() -> u64 {
    std::env::var("WORKER_POLL_SECONDS")
        .ok()
        .and_then(|raw| raw.parse().ok())
        .unwrap_or(5)
}

fn announce(readiness: Readiness, has_storage: bool, has_provider: bool) {
    tracing::info!(
        illustration = readiness.illustration,
        challenge = readiness.challenge,
        sweep = has_storage,
        "job kinds enabled"
    );
    if !readiness.illustration {
        tracing::warn!(
            provider = has_provider,
            object_store = has_storage,
            ai_config = readiness.config,
            "illustration jobs are not being polled"
        );
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct Readiness {
    illustration: bool,
    challenge: bool,
    config: bool,
}

async fn tick(pool: &PgPool, storage: Option<&Storage>, provider: Option<&Provider>) -> Readiness {
    if let Err(error) = prepare(pool).await {
        tracing::error!(
            error.kind = "database",
            "could not prepare the queue: {error}"
        );
        return Readiness {
            illustration: false,
            challenge: false,
            config: false,
        };
    }

    let config = inference::ready(pool, illustration::CAPABILITY)
        .await
        .unwrap_or(false);
    let challenge_config = challenge::ready(pool).await.unwrap_or(false);
    let readiness = Readiness {
        illustration: provider.is_some() && storage.is_some() && config,
        challenge: provider.is_some() && challenge_config,
        config,
    };

    let mut claimed = 0;
    for kind in kinds(
        readiness.illustration,
        storage.is_some(),
        readiness.challenge,
    ) {
        let outcome =
            wardrobe_worker::run_one(pool, kind, |job| handle(pool, storage, provider, job)).await;
        match outcome {
            Ok(Some(outcome)) => {
                claimed += 1;
                tracing::info!(job.kind = kind, ?outcome, "job finished");
            }
            Ok(None) => {}
            Err(error) => {
                tracing::error!(
                    job.kind = kind,
                    error.kind = "database",
                    "claim failed: {error}"
                );
            }
        }
    }
    if claimed == 0 {
        tracing::debug!("queue idle");
    }
    readiness
}

async fn prepare(pool: &PgPool) -> sqlx::Result<()> {
    let mut conn = pool.acquire().await?;
    for kind in kinds(true, true, true) {
        let reclaimed = wardrobe_db::reclaim_stalled(
            &mut conn,
            kind,
            Duration::minutes(wardrobe_worker::STALL_AFTER_MINUTES),
        )
        .await?;
        if reclaimed > 0 {
            tracing::warn!(
                job.kind = kind,
                reclaimed,
                "jobs whose worker never came back"
            );
        }
    }
    drop(conn);

    wardrobe_worker::enqueue_sweep(pool, Utc::now()).await?;
    challenge::enqueue_decks(pool).await?;
    Ok(())
}

async fn handle(
    pool: &PgPool,
    storage: Option<&Storage>,
    provider: Option<&Provider>,
    job: ClaimedJob,
) -> Result<(), &'static str> {
    match job.kind.as_str() {
        wardrobe_db::ILLUSTRATION => {
            let storage = storage.ok_or("object_store_unconfigured")?;
            let provider = provider.ok_or("provider_unconfigured")?;
            let max_attempts: i32 =
                sqlx::query_scalar("select max_attempts from job where id = $1")
                    .bind(job.id)
                    .fetch_one(pool)
                    .await
                    .map_err(|_| "database")?;
            illustration::render_for(pool, storage, provider, &job, job.attempts >= max_attempts)
                .await
        }
        wardrobe_db::CHALLENGE_DECK => {
            let provider = provider.ok_or("provider_unconfigured")?;
            let max_attempts: i32 =
                sqlx::query_scalar("select max_attempts from job where id = $1")
                    .bind(job.id)
                    .fetch_one(pool)
                    .await
                    .map_err(|_| "database")?;
            challenge::generate_for(pool, provider, &job, job.attempts >= max_attempts).await
        }
        wardrobe_db::OUTFIT_TEMPLATE => {
            let storage = storage.ok_or("object_store_unconfigured")?;
            let provider = provider.ok_or("provider_unconfigured")?;
            let max_attempts: i32 =
                sqlx::query_scalar("select max_attempts from job where id = $1")
                    .bind(job.id)
                    .fetch_one(pool)
                    .await
                    .map_err(|_| "database")?;
            template::render_for(pool, storage, provider, &job, job.attempts >= max_attempts).await
        }
        wardrobe_db::STYLISE_ILLUSTRATION => {
            let storage = storage.ok_or("object_store_unconfigured")?;
            illustration::stylise_for(pool, storage, &job).await
        }
        SWEEP_MEDIA => {
            let storage = storage.ok_or("object_store_unconfigured")?;
            let swept =
                wardrobe_worker::sweep_media(pool, storage, Duration::hours(SWEEP_GRACE_HOURS))
                    .await?;
            tracing::info!(
                removed = swept.removed,
                stamped = swept.stamped,
                "swept reserved media"
            );
            Ok(())
        }
        _ => Err("unknown_kind"),
    }
}

async fn sigterm_or_ctrl_c() {
    let Ok(mut term) = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
    else {
        let _ = tokio::signal::ctrl_c().await;
        return;
    };

    tokio::select! {
        _ = term.recv() => {}
        _ = tokio::signal::ctrl_c() => {}
    }
}

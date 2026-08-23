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
use wardrobe_worker::{KINDS, SWEEP_GRACE_HOURS, SWEEP_MEDIA};

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
    let storage = wardrobe_storage::Settings::from_env().map(|settings| Storage::new(&settings));
    let interval = Wait::from_secs(poll_seconds());
    tracing::info!(poll_seconds = interval.as_secs(), "worker started");

    let mut stopping = std::pin::pin!(sigterm_or_ctrl_c());
    loop {
        tick(&pool, storage.as_ref()).await;
        tokio::select! {
            () = &mut stopping => break,
            () = tokio::time::sleep(interval) => {}
        }
    }

    tracing::info!("shutting down after finishing the job in hand");
    Ok(())
}

fn poll_seconds() -> u64 {
    std::env::var("WORKER_POLL_SECONDS")
        .ok()
        .and_then(|raw| raw.parse().ok())
        .unwrap_or(5)
}

async fn tick(pool: &PgPool, storage: Option<&Storage>) {
    if let Err(error) = prepare(pool).await {
        tracing::error!(
            error.kind = "database",
            "could not prepare the queue: {error}"
        );
        return;
    }

    for kind in KINDS {
        let outcome = wardrobe_worker::run_one(pool, kind, |job| handle(pool, storage, job)).await;
        match outcome {
            Ok(Some(outcome)) => tracing::info!(job.kind = kind, ?outcome, "job finished"),
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
}

async fn prepare(pool: &PgPool) -> sqlx::Result<()> {
    let mut conn = pool.acquire().await?;
    for kind in KINDS {
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
    Ok(())
}

async fn handle(
    pool: &PgPool,
    storage: Option<&Storage>,
    job: ClaimedJob,
) -> Result<(), &'static str> {
    match job.kind.as_str() {
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

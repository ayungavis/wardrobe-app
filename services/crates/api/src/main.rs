use std::process::ExitCode;

use sqlx::postgres::PgPoolOptions;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use wardrobe_api::auth::apple;
use wardrobe_api::config::Config;
use wardrobe_observability as observability;

fn main() -> ExitCode {
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::FAILURE;
        }
    };

    let _sentry_guard_outliving_the_runtime = observability::init(&config.observability);

    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer())
        .with(sentry::integrations::tracing::layer())
        .init();

    serve(config)
}

#[tokio::main]
async fn serve(config: Config) -> ExitCode {
    match run(config).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            tracing::error!("{error}");
            ExitCode::FAILURE
        }
    }
}

async fn verified_storage(
    settings: Option<&wardrobe_storage::Settings>,
) -> Result<Option<std::sync::Arc<wardrobe_storage::Storage>>, Box<dyn std::error::Error>> {
    let Some(settings) = settings else {
        tracing::warn!("no object store configured; media endpoints will refuse");
        return Ok(None);
    };

    let storage = std::sync::Arc::new(wardrobe_storage::Storage::new(settings));
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

async fn run(config: Config) -> Result<(), Box<dyn std::error::Error>> {
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await?;

    wardrobe_db::MIGRATOR.run(&pool).await?;
    tracing::info!("migrations applied");

    let storage = verified_storage(config.storage.as_ref()).await?;

    let listener = TcpListener::bind(&config.bind_addr).await?;
    let contract = if config.serve_docs {
        "/docs"
    } else {
        "/openapi.json (SERVE_DOCS is off)"
    };
    tracing::info!(addr = %config.bind_addr, contract, "listening");

    let apple = std::sync::Arc::new(apple::Verifier::new(config.apple_bundle_id.clone()));

    let app = wardrobe_api::app_with(
        pool,
        apple,
        storage,
        config.trusted_proxy_hops,
        config.serve_docs,
    );
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown())
        .await?;
    Ok(())
}

async fn shutdown() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutting down");
}

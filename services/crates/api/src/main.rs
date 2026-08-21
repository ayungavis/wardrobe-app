use std::process::ExitCode;

use sqlx::postgres::PgPoolOptions;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use wardrobe_api::auth::apple;
use wardrobe_api::{config::Config, observability};

fn main() -> ExitCode {
    let config = match Config::from_env() {
        Ok(config) => config,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::FAILURE;
        }
    };

    let _sentry_guard_outliving_the_runtime = observability::init(&config);

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

async fn run(config: Config) -> Result<(), Box<dyn std::error::Error>> {
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await?;

    wardrobe_db::MIGRATOR.run(&pool).await?;
    tracing::info!("migrations applied");

    let listener = TcpListener::bind(&config.bind_addr).await?;
    tracing::info!(addr = %config.bind_addr, "listening; docs at /docs");

    let apple = std::sync::Arc::new(apple::Verifier::new(config.apple_bundle_id.clone()));

    let storage = config
        .storage
        .as_ref()
        .map(|settings| std::sync::Arc::new(wardrobe_storage::Storage::new(settings)));

    axum::serve(listener, wardrobe_api::app(pool, apple, storage))
        .with_graceful_shutdown(shutdown())
        .await?;
    Ok(())
}

async fn shutdown() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutting down");
}

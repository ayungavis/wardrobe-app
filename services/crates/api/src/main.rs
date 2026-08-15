use std::process::ExitCode;

use sqlx::postgres::PgPoolOptions;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;
use wardrobe_api::config::Config;

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            // Startup failures must name the thing that failed; a stack trace
            // helps nobody at 3am.
            tracing::error!("{error}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::from_env()?;

    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&config.database_url)
        .await?;

    // Before the listener opens, so no request ever meets a half-applied
    // schema. sqlx takes an advisory lock, so concurrent instances are safe.
    // A failing migration takes the process down with it, which is the correct
    // outcome: the platform keeps the previous deployment serving rather than
    // promoting an API running against the wrong schema.
    wardrobe_db::MIGRATOR.run(&pool).await?;
    tracing::info!("migrations applied");

    let listener = TcpListener::bind(&config.bind_addr).await?;
    tracing::info!(addr = %config.bind_addr, "listening; docs at /docs");

    axum::serve(listener, wardrobe_api::app(pool))
        .with_graceful_shutdown(shutdown())
        .await?;
    Ok(())
}

/// Lets in-flight requests finish when the container is asked to stop.
async fn shutdown() {
    let _ = tokio::signal::ctrl_c().await;
    tracing::info!("shutting down");
}

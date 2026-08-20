use std::env::{self, VarError};

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub bind_addr: String,
    pub sentry_dsn: Option<String>,
    pub sentry_environment: String,
    pub sentry_traces_sample_rate: f32,
    pub release: Option<String>,
    pub apple_bundle_id: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("environment variable {0} is required")]
    Missing(&'static str),
    #[error("environment variable {0} is not valid UTF-8")]
    NotUnicode(&'static str),
}

impl Config {
    /// # Errors
    ///
    /// Returns [`ConfigError`] when a required variable is absent or unusable.
    pub fn from_env() -> Result<Self, ConfigError> {
        Ok(Self {
            database_url: required("DATABASE_URL")?,
            bind_addr: bind_addr(optional("BIND_ADDR")?, optional("PORT")?),
            sentry_dsn: optional("SENTRY_DSN")?,
            sentry_environment: optional("SENTRY_ENVIRONMENT")?
                .unwrap_or_else(|| "development".to_owned()),
            sentry_traces_sample_rate: optional("SENTRY_TRACES_SAMPLE_RATE")?
                .and_then(|raw| raw.parse().ok())
                .unwrap_or(0.0),
            release: optional("GIT_SHA")?.or(optional("RAILWAY_GIT_COMMIT_SHA")?),
            apple_bundle_id: optional("APPLE_BUNDLE_ID")?,
        })
    }
}

fn bind_addr(explicit: Option<String>, port: Option<String>) -> String {
    match (explicit, port) {
        (Some(addr), _) => addr,
        (None, Some(port)) => format!("0.0.0.0:{port}"),
        (None, None) => "0.0.0.0:8080".to_owned(),
    }
}

fn required(key: &'static str) -> Result<String, ConfigError> {
    optional(key)?.ok_or(ConfigError::Missing(key))
}

fn optional(key: &'static str) -> Result<Option<String>, ConfigError> {
    match env::var(key) {
        Ok(value) if value.is_empty() => Ok(None),
        Ok(value) => Ok(Some(value)),
        Err(VarError::NotPresent) => Ok(None),
        Err(VarError::NotUnicode(_)) => Err(ConfigError::NotUnicode(key)),
    }
}

#[cfg(test)]
mod tests {
    use super::bind_addr;

    #[test]
    fn an_explicit_address_wins() {
        let resolved = bind_addr(Some("127.0.0.1:9000".into()), Some("3000".into()));

        assert_eq!(resolved, "127.0.0.1:9000");
    }

    #[test]
    fn a_platform_port_binds_every_interface() {
        assert_eq!(bind_addr(None, Some("3000".into())), "0.0.0.0:3000");
    }

    #[test]
    fn without_either_it_falls_back_to_a_known_port() {
        assert_eq!(bind_addr(None, None), "0.0.0.0:8080");
    }
}

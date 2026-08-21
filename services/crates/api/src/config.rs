use std::env::{self, VarError};

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub bind_addr: String,
    pub sentry_dsn: Option<String>,
    pub sentry_environment: String,
    pub sentry_traces_sample_rate: f32,
    pub release: Option<String>,
    pub apple_bundle_id: Option<String>,
    pub storage: Option<wardrobe_storage::Settings>,
}

impl std::fmt::Debug for Config {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("Config")
            .field("database_url", &"[redacted]")
            .field("bind_addr", &self.bind_addr)
            .field(
                "sentry_dsn",
                &self.sentry_dsn.as_ref().map(|_| "[redacted]"),
            )
            .field("sentry_environment", &self.sentry_environment)
            .field("sentry_traces_sample_rate", &self.sentry_traces_sample_rate)
            .field("release", &self.release)
            .field("apple_bundle_id", &self.apple_bundle_id)
            .field("storage", &self.storage)
            .finish()
    }
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
            storage: storage()?,
        })
    }
}

fn storage() -> Result<Option<wardrobe_storage::Settings>, ConfigError> {
    let (Some(endpoint), Some(bucket), Some(access_key_id), Some(secret_access_key)) = (
        optional("S3_ENDPOINT")?,
        optional("S3_BUCKET")?,
        optional("S3_ACCESS_KEY_ID")?,
        optional("S3_SECRET_ACCESS_KEY")?,
    ) else {
        return Ok(None);
    };

    Ok(Some(wardrobe_storage::Settings {
        endpoint,
        region: optional("S3_REGION")?.unwrap_or_else(|| "auto".to_owned()),
        bucket,
        access_key_id,
        secret_access_key,
        path_style: optional("S3_FORCE_PATH_STYLE")?
            .is_none_or(|raw| raw.eq_ignore_ascii_case("true")),
        presign_ttl: std::time::Duration::from_secs(
            optional("S3_PRESIGN_SECS")?
                .and_then(|raw| raw.parse().ok())
                .unwrap_or(300),
        ),
    }))
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
    use super::{Config, bind_addr};

    #[test]
    fn debug_output_names_no_secret() {
        let config = Config {
            database_url: "postgres://user:hunter2@host/db".to_owned(),
            bind_addr: "0.0.0.0:8080".to_owned(),
            sentry_dsn: Some("https://key@sentry.io/1".to_owned()),
            sentry_environment: "test".to_owned(),
            sentry_traces_sample_rate: 0.0,
            release: None,
            apple_bundle_id: None,
            storage: Some(wardrobe_storage::Settings {
                endpoint: "http://localhost:9100".to_owned(),
                region: "us-east-1".to_owned(),
                bucket: "wardrobe".to_owned(),
                access_key_id: "AKIAEXAMPLE".to_owned(),
                secret_access_key: "s3cr3t-key".to_owned(),
                path_style: true,
                presign_ttl: std::time::Duration::from_secs(300),
            }),
        };

        let printed = format!("{config:?}");

        for secret in ["hunter2", "key@sentry.io", "AKIAEXAMPLE", "s3cr3t-key"] {
            assert!(
                !printed.contains(secret),
                "a debug line is the easiest place for {secret} to escape: {printed}"
            );
        }
    }

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

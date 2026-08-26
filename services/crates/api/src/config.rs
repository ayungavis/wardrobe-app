use std::env::{self, VarError};

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub bind_addr: String,
    pub observability: wardrobe_observability::Settings,
    pub apple_bundle_id: Option<String>,
    pub storage: Option<wardrobe_storage::Settings>,
    pub trusted_proxy_hops: usize,
    pub serve_docs: bool,
}

impl std::fmt::Debug for Config {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("Config")
            .field("database_url", &"[redacted]")
            .field("bind_addr", &self.bind_addr)
            .field("observability", &self.observability)
            .field("apple_bundle_id", &self.apple_bundle_id)
            .field("storage", &self.storage)
            .field("trusted_proxy_hops", &self.trusted_proxy_hops)
            .field("serve_docs", &self.serve_docs)
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
            observability: wardrobe_observability::Settings::from_env(),
            apple_bundle_id: optional("APPLE_BUNDLE_ID")?,
            storage: wardrobe_storage::Settings::from_env(),
            trusted_proxy_hops: optional("TRUSTED_PROXY_HOPS")?
                .and_then(|raw| raw.parse().ok())
                .unwrap_or(crate::limit::DEFAULT_TRUSTED_HOPS),
            serve_docs: optional("SERVE_DOCS")?.as_deref() == Some("true"),
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
    use super::{Config, bind_addr};

    #[test]
    fn debug_output_names_no_secret() {
        let config = Config {
            database_url: "postgres://user:hunter2@host/db".to_owned(),
            bind_addr: "0.0.0.0:8080".to_owned(),
            observability: wardrobe_observability::Settings {
                dsn: Some("https://key@sentry.io/1".to_owned()),
                environment: "test".to_owned(),
                traces_sample_rate: 0.0,
                release: None,
            },
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
            trusted_proxy_hops: 1,
            serve_docs: false,
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

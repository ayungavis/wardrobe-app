use std::env::{self, VarError};

/// Everything the process needs from its environment, read once at startup.
///
/// Missing configuration fails here with the variable's name rather than
/// surfacing later as a connection error nobody can trace back.
#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub bind_addr: String,
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
    /// Returns [`ConfigError`] naming the first variable that is missing or
    /// unreadable.
    pub fn from_env() -> Result<Self, ConfigError> {
        Ok(Self {
            database_url: required("DATABASE_URL")?,
            bind_addr: optional("BIND_ADDR")?.unwrap_or_else(|| "0.0.0.0:8080".to_owned()),
        })
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

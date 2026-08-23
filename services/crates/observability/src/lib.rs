use std::borrow::Cow;
use std::sync::Arc;

use sentry::ClientInitGuard;
use sentry::protocol::Event;

const REDACTED: &str = "[redacted]";

#[derive(Clone, Default)]
pub struct Settings {
    pub dsn: Option<String>,
    pub environment: String,
    pub traces_sample_rate: f32,
    pub release: Option<String>,
}

impl Settings {
    #[must_use]
    pub fn from_env() -> Self {
        fn var(name: &str) -> Option<String> {
            std::env::var(name).ok().filter(|value| !value.is_empty())
        }

        Self {
            dsn: var("SENTRY_DSN"),
            environment: var("SENTRY_ENVIRONMENT").unwrap_or_else(|| "development".to_owned()),
            traces_sample_rate: var("SENTRY_TRACES_SAMPLE_RATE")
                .and_then(|raw| raw.parse().ok())
                .unwrap_or(0.0),
            release: var("GIT_SHA").or_else(|| var("RAILWAY_GIT_COMMIT_SHA")),
        }
    }
}

impl std::fmt::Debug for Settings {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("Settings")
            .field("dsn", &self.dsn.as_ref().map(|_| REDACTED))
            .field("environment", &self.environment)
            .field("traces_sample_rate", &self.traces_sample_rate)
            .field("release", &self.release)
            .finish()
    }
}

pub fn init(settings: &Settings) -> Option<ClientInitGuard> {
    let dsn = settings
        .dsn
        .as_deref()
        .map(str::trim)
        .filter(|dsn| !dsn.is_empty())?
        .to_owned();

    Some(sentry::init((
        dsn,
        sentry::ClientOptions {
            release: settings.release.clone().map(Cow::from),
            environment: Some(Cow::from(settings.environment.clone())),
            traces_sample_rate: settings.traces_sample_rate,
            send_default_pii: false,
            before_send: Some(Arc::new(scrub)),
            ..sentry::ClientOptions::default()
        },
    )))
}

#[must_use]
pub fn scrub(mut event: Event<'static>) -> Option<Event<'static>> {
    if carries_row_content(&event) {
        return None;
    }

    event.server_name = None;
    if let Some(request) = event.request.as_mut() {
        request.data = None;
        request.cookies = None;
        request.headers.clear();
        request.query_string = request.query_string.take().map(|_| REDACTED.to_owned());
    }

    for exception in &mut event.exception {
        exception.value = exception.value.take().map(|value| redact(&value));
    }
    event.message = event.message.take().map(|message| redact(&message));

    Some(event)
}

fn carries_row_content(event: &Event<'static>) -> bool {
    let texts = event
        .message
        .iter()
        .map(String::as_str)
        .chain(event.exception.iter().filter_map(|e| e.value.as_deref()));

    texts.into_iter().any(|text| {
        text.contains("Failing row contains") || text.contains("Key (") || text.contains("DETAIL:")
    })
}

fn redact(text: &str) -> String {
    let mut out = String::with_capacity(text.len());

    for word in text.split_inclusive(char::is_whitespace) {
        let trimmed = word.trim_end();
        if looks_like_signed_url(trimmed) || looks_like_object_key(trimmed) {
            out.push_str(REDACTED);
            out.push_str(&word[trimmed.len()..]);
        } else {
            out.push_str(word);
        }
    }

    out
}

fn looks_like_signed_url(word: &str) -> bool {
    word.starts_with("http") && (word.contains("X-Amz-") || word.contains("Signature="))
}

fn looks_like_object_key(word: &str) -> bool {
    let mut parts = word.split('/');
    let (Some(prefix), Some(name), None) = (parts.next(), parts.next(), parts.next()) else {
        return false;
    };
    uuid::Uuid::parse_str(prefix).is_ok() && name.split('.').next().is_some_and(is_uuid)
}

fn is_uuid(candidate: &str) -> bool {
    uuid::Uuid::parse_str(candidate).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(text: &str) -> Event<'static> {
        Event {
            message: Some(text.to_owned()),
            ..Event::default()
        }
    }

    #[test]
    fn a_postgres_row_dump_is_dropped_entirely() {
        let event = message(
            "error returned from database: Failing row contains (01a0, Kemeja linen biru, 2026-08-20).",
        );

        assert!(scrub(event).is_none());
    }

    #[test]
    fn a_constraint_detail_line_is_dropped_entirely() {
        assert!(scrub(message("DETAIL: Key (account_id)=(01a0) already exists.")).is_none());
    }

    #[test]
    fn an_object_key_is_redacted_but_the_event_survives() {
        let key = "01a01f2f-68f6-7fc1-a776-4a69b0845f79/01a01f2f-68f0-73d2-90e6-7d4fe4d6e1c8.png";
        let scrubbed = scrub(message(&format!(
            "upload failed for {key} after 3 attempts"
        )))
        .expect("a redactable event is still worth sending");

        let text = scrubbed.message.unwrap();
        assert!(!text.contains(key));
        assert!(text.contains(REDACTED) && text.contains("after 3 attempts"));
    }

    #[test]
    fn a_signed_url_is_redacted() {
        let url = "https://r2.example.com/bucket/obj?X-Amz-Signature=deadbeef";
        let scrubbed = scrub(message(&format!("could not fetch {url}"))).unwrap();

        assert!(!scrubbed.message.unwrap().contains("deadbeef"));
    }

    fn settings(dsn: Option<&str>) -> Settings {
        Settings {
            dsn: dsn.map(str::to_owned),
            environment: "test".to_owned(),
            ..Settings::default()
        }
    }

    #[test]
    fn the_sdk_stays_off_without_a_dsn() {
        assert!(init(&settings(None)).is_none());
        assert!(init(&settings(Some(""))).is_none());
    }

    #[test]
    fn an_ordinary_message_passes_through_unchanged() {
        let scrubbed = scrub(message("migrations applied")).unwrap();

        assert_eq!(scrubbed.message.as_deref(), Some("migrations applied"));
        assert!(scrubbed.server_name.is_none());
    }
}

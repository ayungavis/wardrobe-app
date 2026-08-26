use std::net::IpAddr;
use std::sync::Arc;

use crate::error::Error;
use axum::http::{Request, StatusCode, header};
use axum::response::{IntoResponse, Response};
use tower_governor::key_extractor::KeyExtractor;
use tower_governor::{GovernorError, GovernorLayer, governor::GovernorConfigBuilder};

pub const DEFAULT_TRUSTED_HOPS: usize = 1;

#[derive(Clone, Copy)]
pub struct Caller {
    trusted_hops: usize,
}

impl Caller {
    #[must_use]
    pub fn behind(trusted_hops: usize) -> Self {
        Self { trusted_hops }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Bucket {
    Bearer(Vec<u8>),
    Address(IpAddr),
    Unattributable,
}

impl KeyExtractor for Caller {
    type Key = Bucket;

    fn extract<T>(&self, request: &Request<T>) -> Result<Self::Key, GovernorError> {
        if let Some(token) = bearer(request) {
            return Ok(Bucket::Bearer(crate::auth::hash_token(token)));
        }
        Ok(rightmost_trusted_hop(request, self.trusted_hops)
            .or_else(|| peer(request))
            .map_or(Bucket::Unattributable, Bucket::Address))
    }
}

fn rightmost_trusted_hop<T>(request: &Request<T>, trusted_hops: usize) -> Option<IpAddr> {
    if trusted_hops == 0 {
        return None;
    }
    let chain: Vec<&str> = request
        .headers()
        .get_all("x-forwarded-for")
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(','))
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .collect();

    chain
        .len()
        .checked_sub(trusted_hops)
        .and_then(|index| chain.get(index))
        .and_then(|entry| entry.parse().ok())
}

fn bearer<T>(request: &Request<T>) -> Option<&str> {
    request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split_once(' '))
        .filter(|(scheme, _)| scheme.eq_ignore_ascii_case("bearer"))
        .map(|(_, token)| token.trim())
        .filter(|token| !token.is_empty())
}

fn peer<T>(request: &Request<T>) -> Option<IpAddr> {
    request
        .extensions()
        .get::<axum::extract::ConnectInfo<std::net::SocketAddr>>()
        .map(|info| info.0.ip())
}

/// # Panics
///
/// Panics when the period or burst is zero, which the callers below make
/// impossible.
#[must_use]
pub fn layer(
    per_second: u64,
    burst: u32,
    trusted_hops: usize,
) -> GovernorLayer<Caller, governor::middleware::NoOpMiddleware, axum::body::Body> {
    let config = GovernorConfigBuilder::default()
        .per_second(per_second)
        .burst_size(burst)
        .key_extractor(Caller::behind(trusted_hops))
        .finish()
        .expect("a positive period and burst are compile-time constants here");

    GovernorLayer::new(Arc::new(config)).error_handler(|error| refusal(&error))
}

fn refusal(error: &GovernorError) -> Response {
    let retry_after = match error {
        GovernorError::TooManyRequests { wait_time, .. } => *wait_time,
        _ => 1,
    };
    (
        StatusCode::TOO_MANY_REQUESTS,
        [(header::RETRY_AFTER, retry_after.to_string())],
        axum::Json(Error::TooManyRequests.body()),
    )
        .into_response()
}

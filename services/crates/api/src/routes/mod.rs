// clippy: a handler's error contract is the `responses(...)` list in its
// `#[utoipa::path]`, which reaches clients through openapi.json. A `# Errors`
// section would restate it in a place no client generator reads.
#![allow(clippy::missing_errors_doc)]

pub mod health;
pub mod sessions;
pub mod sync;
pub mod whoami;

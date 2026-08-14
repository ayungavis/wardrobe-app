//! HTTP handlers.
//!
//! A handler's rustdoc becomes its `OpenAPI` description, so `# Errors` sections
//! are suppressed here: for an endpoint, the failure contract is the
//! `responses(...)` block, and duplicating it in prose would leak Rust-only
//! detail into the document clients read.
#![allow(clippy::missing_errors_doc)]

pub mod health;
pub mod session;

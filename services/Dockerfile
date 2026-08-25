FROM rust:1.98-slim AS builder

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build

COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY crates/api/Cargo.toml crates/api/Cargo.toml
COPY crates/db/Cargo.toml crates/db/Cargo.toml
COPY crates/observability/Cargo.toml crates/observability/Cargo.toml
COPY crates/storage/Cargo.toml crates/storage/Cargo.toml
COPY crates/worker/Cargo.toml crates/worker/Cargo.toml
RUN mkdir -p crates/api/src/bin crates/db/src crates/observability/src \
        crates/storage/src crates/worker/src \
    && echo 'fn main() {}' > crates/api/src/main.rs \
    && echo 'fn main() {}' > crates/api/src/bin/openapi.rs \
    && echo 'fn main() {}' > crates/worker/src/main.rs \
    && touch crates/api/src/lib.rs crates/db/src/lib.rs \
        crates/observability/src/lib.rs crates/storage/src/lib.rs crates/worker/src/lib.rs \
    && cargo build --release --locked --bin wardrobe-api --bin wardrobe-worker \
    && rm -rf crates/api/src crates/db/src crates/observability/src \
        crates/storage/src crates/worker/src

COPY crates crates
COPY migrations migrations

RUN touch crates/api/src/main.rs crates/db/src/lib.rs crates/observability/src/lib.rs \
        crates/storage/src/lib.rs crates/worker/src/main.rs \
    && cargo build --release --locked --bin wardrobe-api --bin wardrobe-worker

# ponytail: debian-slim keeps a shell, which is worth having the first time a
# deployment misbehaves. Measured 206 MB on arm64, of which the two binaries are
# 43 MB and the rest is this base — swap to gcr.io/distroless/cc once remote
# debugging is no longer needed.
FROM debian:trixie-slim AS runtime
# ca-certificates is not optional: without it, TLS to a managed PostgreSQL — and
# later to OpenRouter — fails with a certificate error that reads like a bug.
RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --user-group --uid 10001 wardrobe
USER wardrobe
WORKDIR /app

COPY --from=builder /build/target/release/wardrobe-api /usr/local/bin/wardrobe-api
COPY --from=builder /build/target/release/wardrobe-worker /usr/local/bin/wardrobe-worker

ENV RUST_LOG=info
EXPOSE 8080
CMD ["wardrobe-api"]

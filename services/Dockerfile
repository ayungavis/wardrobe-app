# Build context is `services/` — set Root Directory to `services` in Railway,
# or the build pulls in the 779 MB iOS app and its LFS-tracked Core ML weights.

FROM rust:1.94-slim AS builder
# utoipa-swagger-ui downloads the Swagger UI assets in its build script and
# shells out to curl to do it, which the slim image does not ship. Without this
# the build fails inside a build.rs panic that says nothing about Docker.
RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build

# Dependencies first, against a dummy source tree: this layer is cached until a
# manifest actually changes, so an ordinary code edit no longer recompiles the
# entire dependency graph.
COPY Cargo.toml Cargo.lock ./
COPY crates/api/Cargo.toml crates/api/Cargo.toml
COPY crates/db/Cargo.toml crates/db/Cargo.toml
COPY crates/storage/Cargo.toml crates/storage/Cargo.toml
RUN mkdir -p crates/api/src/bin crates/db/src crates/storage/src \
    && echo 'fn main() {}' > crates/api/src/main.rs \
    && echo 'fn main() {}' > crates/api/src/bin/openapi.rs \
    && touch crates/api/src/lib.rs crates/db/src/lib.rs crates/storage/src/lib.rs \
    && cargo build --release --locked --bin wardrobe-api \
    && rm -rf crates/api/src crates/db/src crates/storage/src

COPY crates crates
COPY migrations migrations
# The dummy files above leave stale fingerprints; touching the real sources
# forces a rebuild of our crates without touching the cached dependencies.
RUN touch crates/api/src/main.rs crates/db/src/lib.rs crates/storage/src/lib.rs \
    && cargo build --release --locked --bin wardrobe-api

# ponytail: debian-slim keeps a shell, which is worth having the first time a
# deployment misbehaves. The image is ~170 MB, almost all of it this base — swap
# to gcr.io/distroless/cc (~20 MB) once remote debugging is no longer needed.
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

# Migrations are embedded in the binary at compile time (sqlx::migrate!), so the
# image needs no SQL files and no sqlx-cli.
#
# No HEALTHCHECK here: the platform probes /health through railway.json, and two
# mechanisms checking the same thing is two places to get it wrong.
ENV RUST_LOG=info
EXPOSE 8080
CMD ["wardrobe-api"]

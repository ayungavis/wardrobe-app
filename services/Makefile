-include .env
export

DATABASE_URL ?= postgres://wardrobe:wardrobe@localhost:5433/wardrobe
S3_ENDPOINT ?= http://localhost:9100
S3_REGION ?= us-east-1
S3_BUCKET ?= wardrobe
S3_ACCESS_KEY_ID ?= wardrobe
S3_SECRET_ACCESS_KEY ?= wardrobe-dev-secret
S3_FORCE_PATH_STYLE ?= true
OPENROUTER_BASE_URL ?= https://openrouter.ai/api/v1

.PHONY: up down migrate reset run worker openapi test fmt lint validate build image

up:
	docker compose up -d --wait

down:
	docker compose down

migrate: up
	sqlx migrate run --source migrations --database-url '$(DATABASE_URL)'

# Drops and rebuilds from empty — the only way to know the migrations still
# apply to a fresh database rather than only to yours.
reset:
	sqlx database drop -y --database-url '$(DATABASE_URL)' || true
	sqlx database create --database-url '$(DATABASE_URL)'
	$(MAKE) migrate

run: up
	cargo run -p wardrobe-api --bin wardrobe-api

worker: up
	cargo run -p wardrobe-worker

# Regenerated from the handlers, never hand-edited. A test fails when the
# committed file drifts from the code.
openapi:
	cargo run --quiet -p wardrobe-api --bin openapi > openapi.json

test: up
	cargo test --workspace

live-ai:
	cargo test -p wardrobe-worker --test illustration -- --ignored --nocapture

fmt:
	cargo fmt --all

lint:
	cargo clippy --workspace --all-targets -- -D warnings

build:
	cargo build --release --locked --bin wardrobe-api --bin wardrobe-worker

image:
	docker build -t wardrobe-backend:local .

validate: fmt lint test

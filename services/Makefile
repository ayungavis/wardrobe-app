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

.PHONY: up down migrate reset run worker seed-ai openapi test fmt lint validate build image

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

seed-ai: up
	@test -n "$(OPENROUTER_TEST_MODEL)" || { echo "set OPENROUTER_TEST_MODEL in services/.env"; exit 1; }
	docker compose exec -T postgres psql -U wardrobe -d wardrobe \
		-c "insert into ai_provider_allowlist (provider_slug, forbids_training, retention_policy, approved_by) values ('openrouter', true, 'zero', 'local-dev') on conflict (provider_slug) do nothing;" \
		-c "insert into ai_model_config (capability, model_class, active_model, prompt_version, updated_by) values ('illustration', 'image', '$(OPENROUTER_TEST_MODEL)', 'p1', 'local-dev') on conflict (capability) do update set active_model = excluded.active_model, updated_at = now(), updated_by = 'local-dev';"

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

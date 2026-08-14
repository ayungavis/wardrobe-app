-include .env
export

DATABASE_URL ?= postgres://wardrobe:wardrobe@localhost:5433/wardrobe

.PHONY: up down migrate reset test fmt lint validate

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

test: up
	cargo test --workspace

fmt:
	cargo fmt --all

lint:
	cargo clippy --workspace --all-targets -- -D warnings

validate: fmt lint test

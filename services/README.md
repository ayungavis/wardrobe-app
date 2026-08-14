# services

The Rust backend: one Cargo workspace, PostgreSQL as the transactional system of record and job
queue, S3-compatible object storage (MinIO locally, Cloudflare R2 in production).

Schema design and the reasoning behind it: [`docs/backend-schema.md`](../docs/backend-schema.md).

## Layout

```
compose.yaml       Postgres 17 + MinIO; the same file is used on the production VPS
migrations/        sqlx migrations, forward-only
openapi.json       generated from the handlers, committed, drift-tested
crates/db/         schema access: the change-feed counter and the job claim
crates/api/        the HTTP API
```

The queue worker is not written yet. API decisions that OpenAPI cannot express are in
[`docs/api-contract.md`](../docs/api-contract.md).

## Getting started

```bash
cp .env.example .env    # local ports: Postgres 5433, MinIO 9100/9101
make up                 # start Postgres and MinIO, wait until healthy
make migrate            # apply migrations
make run                # serve the API — Swagger UI at http://localhost:8080/docs
make validate           # fmt + clippy -D warnings + tests
```

`make openapi` regenerates `openapi.json`; a test fails when the committed file drifts from the
handlers, so documentation cannot go stale unnoticed.

`make reset` drops and rebuilds the database from empty — the only way to know the migrations
still apply to a fresh machine and not just to yours.

Tests use `#[sqlx::test]`, which creates a throwaway database per test, so they need `make up`
but never a hand-migrated database.

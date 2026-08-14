# services

The Rust backend: one Cargo workspace, PostgreSQL as the transactional system of record and job
queue, S3-compatible object storage (MinIO locally, Cloudflare R2 in production).

Schema design and the reasoning behind it: [`docs/backend-schema.md`](../docs/backend-schema.md).

## Layout

```
compose.yaml       Postgres 17 + MinIO; the same file is used on the production VPS
migrations/        sqlx migrations, forward-only
crates/db/         schema access: the change-feed counter and the job claim
```

The API and worker binaries are not written yet; the schema comes first.

## Getting started

```bash
cp .env.example .env    # local ports: Postgres 5433, MinIO 9100/9101
make up                 # start Postgres and MinIO, wait until healthy
make migrate            # apply migrations
make validate           # fmt + clippy -D warnings + tests
```

`make reset` drops and rebuilds the database from empty — the only way to know the migrations
still apply to a fresh machine and not just to yours.

Tests use `#[sqlx::test]`, which creates a throwaway database per test, so they need `make up`
but never a hand-migrated database.

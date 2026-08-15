# Deployment

> How the API gets to production, what happens when it boots, and how to read a failure.
>
> **Target: Railway.** This replaces the single-VPS + Docker Compose plan in PRD §20; the delta
> the PRD needs is in [prd-railway-delta.md](prd-railway-delta.md). Compose stays exactly as it
> is for local development.

## 1. What runs

| Piece | Where |
| --- | --- |
| API (`wardrobe-api`) | Railway service, built from `services/Dockerfile` |
| PostgreSQL | Railway Postgres plugin |
| Object storage | **Cloudflare R2** — Railway has no MinIO equivalent, and production was always going to be R2 (PRD §20). MinIO stays local-only |
| Queue worker | Not written yet. When it exists it is a second Railway service from the same image with a different command |

## 2. One-time setup

1. New Railway project → **Deploy from GitHub repo**.
2. **Set Root Directory to `services`.** Without this, Railway builds from the repo root and drags
   in the 779 MB iOS app together with its LFS-tracked Core ML weights. This is the single most
   important setting here and it cannot be committed to a file.
3. Add the **PostgreSQL** plugin to the project.
4. Set the service variables:

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Reference the Postgres plugin: `${{Postgres.DATABASE_URL}}` |
| `RUST_LOG` | `info` (or `wardrobe_api=debug,info` while diagnosing) |
| `PORT` | **Do not set.** Railway injects it |

`services/railway.json` supplies the rest: Dockerfile builder, `/health` as the health check, and
restart-on-failure with three retries.

## 3. What happens on boot

```
Config::from_env()          →  fails immediately, naming the missing variable
connect PostgreSQL          →  pool of 10
MIGRATOR.run(&pool)         →  applies any new migrations, under an advisory lock
bind 0.0.0.0:$PORT          →  only now can traffic arrive
```

Two consequences worth knowing before the first bad night:

- **Migrations run automatically, before the listener opens.** No request ever meets a
  half-applied schema, and several instances starting at once cannot collide — sqlx takes an
  advisory lock.
- **A failed migration takes the process down.** That is correct: Railway keeps the previous
  deployment serving when the new one fails to start, so a broken migration is a rollback rather
  than an API running against the wrong schema.

`PORT` is bound on `0.0.0.0`. Binding loopback would produce a process that looks healthy to
itself and never receives a single request — which is why the resolution order is a tested
function (`config::bind_addr`) rather than a string built inline.

## 4. Reading failures

| Symptom | Cause |
| --- | --- |
| Deploy fails instantly, log says `environment variable DATABASE_URL is required` | The Postgres reference is missing or misspelled |
| Health check times out, no request logs | Something bound loopback, or `PORT` was set by hand to a port Railway does not route |
| `error returned from database` during boot | A migration failed. The previous deployment is still serving; fix forward with a new migration file |
| TLS or certificate errors reaching Postgres | `ca-certificates` missing from the runtime image — it is installed in the Dockerfile for exactly this reason |
| Build pulls hundreds of megabytes | Root Directory is not set to `services` |

## 5. The image

Multi-stage: `rust:1.94-slim` builds, `debian:trixie-slim` runs.

- Dependencies compile in their own cached layer, so an ordinary code change does not rebuild the
  whole dependency graph.
- `--locked`, so production builds use the same `Cargo.lock` that was tested.
- Only `--bin wardrobe-api`; the OpenAPI generator is a development tool.
- Runs as a non-root user.
- Migrations are embedded in the binary by `sqlx::migrate!`, so the image carries no SQL files and
  no `sqlx-cli`.
- The builder installs `curl` because `utoipa-swagger-ui` downloads the Swagger assets in its
  build script — without it the build dies inside a `build.rs` panic that mentions nothing about
  Docker.

**Size: ~170 MB**, and nearly all of it is the Debian base. Keeping a shell is worth that while
the deployment is new; `gcr.io/distroless/cc` would cut it to roughly 20 MB once remote debugging
is no longer useful. Marked `ponytail:` in the Dockerfile.

Verify the image locally before trusting a deploy:

```bash
docker build -t wardrobe-api services/
docker run --rm -p 3000:3000 \
  -e PORT=3000 \
  -e DATABASE_URL='postgres://wardrobe:wardrobe@host.docker.internal:5433/wardrobe' \
  wardrobe-api
curl -s localhost:3000/health     # {"status":"ok"}
```

## 6. After the deploy

- `https://<service>.up.railway.app/health` → `{"status":"ok"}`
- `https://<service>.up.railway.app/docs` → Swagger UI
- `https://<service>.up.railway.app/openapi.json` → the contract clients generate from

Swagger UI is deliberately left on in production. API documentation is not the secret; the data
is, and that stays behind authentication.

## 7. Not done yet

- **R2 credentials and the media endpoints** — nothing uploads or downloads objects yet.
- **The queue worker** as a second service.
- **Backups.** Railway's Postgres backup policy has to be chosen and written down; PRD §28 still
  lists the recovery objectives as an open question.
- **A custom domain and TLS termination**, if the app should not talk to a `railway.app` host.

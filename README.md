# Wardrobe Challenge App

An iOS app that helps people in their 20s re-wear clothes they already own through one creative Outfit-of-the-Day challenge per day. The wardrobe builds itself progressively from completed challenge photos — no upfront cataloguing.

**Product behavior is defined in [`docs/prd.md`](docs/prd.md) — read it before building features.**

Two sides, developed independently: an **iOS app** and a **Rust backend**. You only need the toolchain for the side you are touching.

```
.
├── app/WardrobeApp/                   iOS app
│   ├── project.yml                    XcodeGen spec — source of truth for the Xcode project
│   ├── WardrobeApp/                   App target: @main entry (Sentry init), assets, xcconfigs
│   └── WardrobeKit/                   Local Swift package — all real code lives here
│       ├── Sources/DesignSystem/      Colors, typography, spacing, shadows, components
│       ├── Sources/WardrobeKit/       Core + Features (MVVM) + AppContainer + localization
│       └── Tests/WardrobeKitTests/    Unit tests (Swift Testing)
├── services/                          Rust backend
│   ├── compose.yaml                   Postgres 17 + MinIO — same file used on the VPS
│   ├── migrations/                    sqlx migrations, forward-only
│   └── crates/db/                     Schema access + the tests that pin its constraints
├── docs/                              PRD and design documents (see below)
└── Makefile                           Every dev command, namespaced ios-* / backend-*
```

## Prerequisites

**iOS**

- **Xcode 26+** (iOS 26 SDK)
- `brew install xcodegen swiftlint swiftformat`

**Backend**

- **Docker** (Postgres and MinIO run in containers)
- **Rust stable** — <https://rustup.rs>
- `cargo install sqlx-cli --no-default-features --features postgres,rustls`

## Getting started

Run `make` at any time for the full command list.

### iOS

```bash
git clone https://github.com/ayungavis/wardrobe-app && cd wardrobe-app

make ios-generate                              # the .xcodeproj is gitignored — never committed
open app/WardrobeApp/WardrobeApp.xcodeproj
```

Or without Xcode, on the booted simulator:

```bash
make ios-run
```

**Signing:** the simulator needs no signing — you can build and run immediately. To run on a **physical device**, set your personal team once in a gitignored file (survives `make ios-generate`, never committed):

```bash
# app/WardrobeApp/WardrobeApp/Config/Local.xcconfig  (find your team ID in Xcode ▸ Settings ▸ Accounts)
echo 'DEVELOPMENT_TEAM = YOUR_TEAM_ID' > app/WardrobeApp/WardrobeApp/Config/Local.xcconfig
make ios-generate
```

The Release configuration is signed manually with the CI team (`QHL64K2LPL`) for TestFlight — don't touch it. ⚠️ Never edit the `.xcodeproj` directly — XcodeGen overwrites it; `project.yml` is the only source of truth.

### Backend

```bash
make backend-up        # Postgres + MinIO, waits until both are healthy
make backend-migrate   # apply the schema
make backend-run       # serve the API
make backend-validate  # fmt + clippy -D warnings + tests
```

With the API running: <http://localhost:8080/docs> is Swagger UI and
<http://localhost:8080/health> reports whether the service *and its database* are reachable.

`services/.env` is created from `.env.example` on first use. Local ports are deliberately **not** the defaults — Postgres is on **5433** and MinIO on **9100/9101**, because a system Postgres on 5432 is common enough that sharing it would be the first thing every new machine tripped over.

**API documentation is generated from the handlers.** [`services/openapi.json`](services/openapi.json) is committed and a test fails if it drifts from the code, so client generators can read it without running anything. Regenerate with `make backend-openapi`.

The queue worker is not written yet, and the API so far serves health, identity, and its own documentation. See [`docs/backend-schema.md`](docs/backend-schema.md) and [`docs/api-contract.md`](docs/api-contract.md).

## Commands

| Command                | What it does                                                                    |
| ---------------------- | ------------------------------------------------------------------------------- |
| `make`                 | List every target with its description                                          |
| `make ios-generate`    | Regenerate `WardrobeApp.xcodeproj` (run after clone / editing `project.yml`)    |
| `make ios-format`      | SwiftFormat the whole repo                                                      |
| `make ios-lint`        | SwiftLint in strict mode                                                        |
| `make ios-test`        | Unit tests via `swift test` — no simulator needed                               |
| `make ios-build`       | Build for iPhone simulator (full log: `/tmp/wardrobeapp-build.log`)             |
| `make ios-run`         | Build + install + launch on the booted simulator                                |
| `make ios-validate`    | format → lint → test → build                                                    |
| `make backend-up`      | Start Postgres and MinIO                                                        |
| `make backend-down`    | Stop them                                                                       |
| `make backend-migrate` | Apply migrations                                                                |
| `make backend-reset`   | Drop and rebuild the database from empty                                        |
| `make backend-run`     | Serve the API — Swagger UI at `/docs`                                           |
| `make backend-openapi` | Regenerate `services/openapi.json` from the handlers                            |
| `make backend-test`    | `cargo test` (starts the containers it needs)                                   |
| `make backend-validate`| fmt → clippy → test                                                             |
| `make validate`        | Both sides. **Must pass before every PR.**                                      |

## CI

GitHub Actions is split by path, so a change to one side never runs the other's jobs:

| Workflow                             | Fires on                                                             |
| ------------------------------------ | -------------------------------------------------------------------- |
| `.github/workflows/ios.yml`          | `app/**`, `Makefile`, lint/format config, `.gitattributes`           |
| `.github/workflows/backend.yml`      | `services/**`                                                        |
| `.github/workflows/testflight.yml`   | Same paths as iOS, on push to `main` — auto-deploys to TestFlight     |

A docs-only change runs nothing. One-time TestFlight credential setup: [`docs/testflight-setup.md`](docs/testflight-setup.md).

## Documents

| Document                                                                 | What it covers                                                          |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [`docs/prd.md`](docs/prd.md)                                             | **The source of truth for product behavior.** Read first                |
| [`docs/backend-schema.md`](docs/backend-schema.md)                       | PostgreSQL schema and why each part is shaped that way                  |
| [`docs/api-contract.md`](docs/api-contract.md)                           | API decisions OpenAPI cannot express: auth, cursor, idempotency, errors  |
| [`docs/wardrobe-generation.md`](docs/wardrobe-generation.md)             | The device/server split for detection, matching, and illustration       |
| [`docs/garment-matching-accuracy.md`](docs/garment-matching-accuracy.md) | What to do when duplicate matching gets it wrong, in cost order         |
| [`docs/capture-editor-share.md`](docs/capture-editor-share.md)           | The camera → editor → share slice                                       |
| [`docs/testflight-setup.md`](docs/testflight-setup.md)                   | One-time App Store Connect credential setup                             |

## Technical notes

### iOS

- **Architecture: MVVM + `@Observable`.** ViewModels are `@MainActor @Observable`, expose a `Loadable<T>` state (`idle/loading/loaded/failed`), and cancel stale tasks on reload — `ChallengeViewModel` is the reference implementation. Views own their ViewModel via `@State private`.
- **All real code lives in the `WardrobeKit` package**; the app target is just the entry point. Dependencies are protocols wired in `AppContainer` (composition root). Repositories are mocks until the backend exists.
- **DesignSystem target** holds every visual token: `AppColor` (light/dark variants in the asset catalog), `AppFont` (Dynamic Type-aware), `Spacing`, `.appShadow()`, and reusable components. Hardcoded `Color`/font/spacing literals in views are forbidden.
- **Localization:** all UI strings go through `Localizable.xcstrings` (English base + Indonesian) with `bundle: .module`. Adding a language = add it in the String Catalog **and** in `CFBundleLocalizations` in `project.yml`. Test with launch argument `-AppleLanguages "(id)"`.
- **Environment config:** values flow `Config/{Debug,Release}.xcconfig` → Info.plist → `Bundle.main`. No secrets in code. `SENTRY_DSN` empty = Sentry stays off (fine for local dev); fill it to enable crash reporting. Non-fatal errors go through `Log.report(_:)` which forwards to Sentry.
- **Logging:** `Log.app` / `Log.network` / `Log.ui` (os.Logger — visible in Console.app and Instruments). Never log photos, search queries, or raw item names (PRD §18).
- **Testing:** Swift Testing (not XCTest) in `WardrobeKitTests`. The package also compiles for macOS solely so `make ios-test` runs on the host without a simulator — iOS-only APIs need an `#if os(iOS)` gate.

### Backend

- **Rust + Axum + sqlx + PostgreSQL**, one workspace, eventually two binaries: an HTTP API and a queue worker. Neither is written yet — the schema came first, and it is tested on its own.
- **PostgreSQL is both the system of record and the job queue.** Jobs are claimed with `for update skip locked`; there is no external broker in the MVP.
- **Object storage is S3-compatible from day one** — MinIO locally, Cloudflare R2 in production — and media is only ever served through short-lived signed URLs.
- **The schema enforces the product rules**, so `services/crates/db/tests/schema.rs` tests constraints rather than helpers: one completion per user-local day, one wear per occurrence, immutable fingerprint versions, one claimant per job. Each test runs against its own throwaway database.

## Troubleshooting

| Symptom                                                      | Fix                                                                                                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Xcode: "Signing for WardrobeApp requires a development team" | Set your team — see _Getting started ▸ iOS ▸ Signing_                                                                                                   |
| Simulator: "Requires a newer version of iOS"                 | Simulator runtime is older than the deployment target — update the runtime (Xcode ▸ Settings ▸ Components) or lower `deploymentTarget` in `project.yml` |
| `make ios-build` fails with no obvious error                 | Full log is at `/tmp/wardrobeapp-build.log`                                                                                                             |
| Project won't open / files missing in Xcode                  | Re-run `make ios-generate` — the `.xcodeproj` is generated and gitignored                                                                                |
| `make backend-up`: "port is already allocated"               | Something else holds 5433 or 9100 — change the port in `services/.env`, then `make backend-down && make backend-up`                                     |
| `make backend-*`: "Cannot connect to the Docker daemon"      | Docker Desktop is not running                                                                                                                           |
| `make backend-migrate`: `sqlx: command not found`            | `cargo install sqlx-cli --no-default-features --features postgres,rustls`                                                                                |

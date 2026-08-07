# Wardrobe Challenge App

An iOS app that helps people in their 20s re-wear clothes they already own through one creative Outfit-of-the-Day challenge per day. The wardrobe builds itself progressively from completed challenge photos — no upfront cataloguing.

**Product behavior is defined in [`docs/prd.md`](docs/prd.md) — read it before building features.**

```
.
├── app/WardrobeApp/
│   ├── project.yml            XcodeGen spec — source of truth for the Xcode project
│   ├── WardrobeApp/           App target: @main entry (Sentry init), assets, xcconfigs
│   └── WardrobeKit/           Local Swift package — all real code lives here
│       ├── Sources/DesignSystem/   Colors, typography, spacing, shadows, components
│       ├── Sources/WardrobeKit/    Core + Features (MVVM) + AppContainer + localization
│       └── Tests/WardrobeKitTests/ Unit tests (Swift Testing)
├── services/                  Rust Axum + PostgreSQL backend (planned, empty)
├── docs/prd.md                MVP Product Requirements Document
└── Makefile                   Every dev/CI command
```

## Prerequisites

- **Xcode 26+** (iOS 26 SDK)
- Homebrew tools:

```bash
brew install xcodegen swiftlint swiftformat
```

## Getting started

```bash
git clone https://github.com/ayungavis/wardrobe-app && cd wardrobe-app

# 1. Generate the Xcode project (it is gitignored — never committed)
make generate

# 2. Open it
open app/WardrobeApp/WardrobeApp.xcodeproj
```

**Signing (first build in Xcode):** the generated project has no development team. Either select your team once in _Signing & Capabilities_, or set it permanently in `app/WardrobeApp/project.yml`:

```yaml
targets:
  WardrobeApp:
    settings:
      base:
        DEVELOPMENT_TEAM: YOUR_TEAM_ID # Xcode ▸ Settings ▸ Accounts
        CODE_SIGN_STYLE: Automatic
```

then re-run `make generate`. ⚠️ Never edit the `.xcodeproj` directly — XcodeGen overwrites it; `project.yml` is the only source of truth.

Run without Xcode (uses the booted simulator):

```bash
make run
```

## Makefile commands

| Command         | What it does                                                                                  |
| --------------- | --------------------------------------------------------------------------------------------- |
| `make generate` | Regenerate `WardrobeApp.xcodeproj` from `project.yml` (run after clone / editing project.yml) |
| `make format`   | SwiftFormat the whole repo                                                                    |
| `make lint`     | SwiftLint in strict mode                                                                      |
| `make test`     | Unit tests via `swift test` — no simulator needed                                             |
| `make build`    | Build for iPhone simulator (full log: `/tmp/wardrobeapp-build.log`)                           |
| `make run`      | Build + install + launch on the booted simulator                                              |
| `make validate` | format → lint → test → build. **Must pass before every PR.**                                  |

CI (GitHub Actions) runs the same targets: `make lint`, `make test`, `make build`.

## Technical notes

- **Architecture: MVVM + `@Observable`.** ViewModels are `@MainActor @Observable`, expose a `Loadable<T>` state (`idle/loading/loaded/failed`), and cancel stale tasks on reload — `ChallengeViewModel` is the reference implementation. Views own their ViewModel via `@State private`.
- **All real code lives in the `WardrobeKit` package**; the app target is just the entry point. Dependencies are protocols wired in `AppContainer` (composition root). Repositories are mocks until the backend exists.
- **DesignSystem target** holds every visual token: `AppColor` (light/dark variants in the asset catalog), `AppFont` (Dynamic Type-aware), `Spacing`, `.appShadow()`, and reusable components. Hardcoded `Color`/font/spacing literals in views are forbidden.
- **Localization:** all UI strings go through `Localizable.xcstrings` (English base + Indonesian) with `bundle: .module`. Adding a language = add it in the String Catalog **and** in `CFBundleLocalizations` in `project.yml`. Test with launch argument `-AppleLanguages "(id)"`.
- **Environment config:** values flow `Config/{Debug,Release}.xcconfig` → Info.plist → `Bundle.main`. No secrets in code. `SENTRY_DSN` empty = Sentry stays off (fine for local dev); fill it to enable crash reporting. Non-fatal errors go through `Log.report(_:)` which forwards to Sentry.
- **Logging:** `Log.app` / `Log.network` / `Log.ui` (os.Logger — visible in Console.app and Instruments). Never log photos, search queries, or raw item names (PRD §18).
- **Testing:** Swift Testing (not XCTest) in `WardrobeKitTests`. The package also compiles for macOS solely so `make test` runs on the host without a simulator — iOS-only APIs need an `#if os(iOS)` gate.

## Troubleshooting

| Symptom                                                      | Fix                                                                                                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Xcode: "Signing for WardrobeApp requires a development team" | Set your team — see _Getting started ▸ Signing_                                                                                                         |
| Simulator: "Requires a newer version of iOS"                 | Simulator runtime is older than the deployment target — update the runtime (Xcode ▸ Settings ▸ Components) or lower `deploymentTarget` in `project.yml` |
| `make build` fails with no obvious error                     | Full log is at `/tmp/wardrobeapp-build.log`                                                                                                             |
| Project won't open / files missing in Xcode                  | Re-run `make generate` — the `.xcodeproj` is generated and gitignored                                                                                   |

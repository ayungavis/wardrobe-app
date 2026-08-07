# TestFlight auto-deploy setup

Every push to `main` (or a manual run of the **testflight** workflow) archives the app, signs it, and uploads it to TestFlight. The pipeline is raw `xcodebuild` + [Apple-Actions](https://github.com/Apple-Actions) — no fastlane. This is the one-time setup it needs.

## 1. One-time Apple setup

All of this happens with an **Admin** (or App Manager) role on the Apple Developer / App Store Connect team `QHL64K2LPL`.

### App record
1. [App Store Connect ▸ Apps ▸ +](https://appstoreconnect.apple.com/apps) — create an app for bundle ID `com.ayungavis.WardrobeApp` (register the bundle ID first at [Developer ▸ Identifiers](https://developer.apple.com/account/resources/identifiers/list) if it's not there).

### Distribution certificate (.p12)
1. [Developer ▸ Certificates](https://developer.apple.com/account/resources/certificates/list) ▸ + ▸ **Apple Distribution**.
2. Follow the CSR steps (Keychain Access ▸ Certificate Assistant ▸ Request a Certificate…), download the `.cer`, double-click to install.
3. In Keychain Access, expand the certificate, select certificate **and** private key ▸ right-click ▸ Export → `WardrobeApp.p12` with a strong password.

### Provisioning profile
1. [Developer ▸ Profiles](https://developer.apple.com/account/resources/profiles/list) ▸ + ▸ **App Store** (distribution — *not* Development).
2. App ID: `com.ayungavis.WardrobeApp`; certificate: the Apple Distribution cert above.
3. Name it exactly **`WardrobeApp Apple Distribution`** — the workflow references this name verbatim (`PROVISIONING_PROFILE_NAME` in `.github/workflows/testflight.yml`).

### App Store Connect API key (.p8)
1. [App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) ▸ generate a **Team key** with role **App Manager**.
2. Download the `.p8` (only downloadable once) and note the **Key ID** and **Issuer ID** shown on that page.

## 2. GitHub configuration

Repo ▸ Settings ▸ Secrets and variables ▸ Actions. Note the split — two values are **variables**, not secrets:

| Name | Kind | Value |
| --- | --- | --- |
| `APPSTORE_CERTIFICATES_FILE_BASE64` | **Secret** | `base64 -i WardrobeApp.p12 \| pbcopy` |
| `APPSTORE_CERTIFICATES_PASSWORD` | **Secret** | The .p12 export password |
| `APPSTORE_API_PRIVATE_KEY` | **Secret** | Raw contents of the `.p8` file (`cat AuthKey_XXX.p8 \| pbcopy`) — **not** base64 |
| `APPSTORE_ISSUER_ID` | **Variable** | Issuer ID from the API keys page |
| `APPSTORE_API_KEY_ID` | **Variable** | Key ID of the generated key |

## 3. Test it

1. Run the workflow manually: Actions ▸ **testflight** ▸ Run workflow (or push to `main`).
2. The "Validate App Store Connect credentials" step fails fast with a readable message if a secret/variable is missing.
3. On success, the build appears in App Store Connect ▸ TestFlight within ~10 minutes (processing time included).

Build numbers come from `github.run_number` — no manual bumping. The marketing version (`1.0`) lives in `app/WardrobeApp/project.yml` (`MARKETING_VERSION`) and is bumped by hand per release.

## Failure modes

| Error | Cause / fix |
| --- | --- |
| `Missing GitHub variable/secret …` | Step 2 incomplete — check the secret **vs variable** split |
| `security: SecKeychainItemImport: MAC verification failed` | Wrong `APPSTORE_CERTIFICATES_PASSWORD` or corrupted base64 — re-export and re-encode the .p12 |
| `No profiles for 'com.ayungavis.WardrobeApp' were found` | Profile is missing, expired, or is a *Development* profile — it must be **App Store**, named `WardrobeApp Apple Distribution` |
| `error: exportArchive: … requires a provisioning profile` | Profile name in the workflow doesn't match the actual profile name exactly |
| Upload rejected: build number already used | Re-run creates the same `run_number` — push a new commit, or the workflow file was renamed (resets `run_number`) |
| `failed downloading … badResponseStatusCode(500)` | Flaky GitHub release download of the Sentry binary — the resolve step retries 3×; re-run the job if it still fails |

## Rotating credentials

- **Certificate expired/revoked:** repeat the certificate + profile steps (a new cert invalidates the old profile), update `APPSTORE_CERTIFICATES_FILE_BASE64` + `APPSTORE_CERTIFICATES_PASSWORD`.
- **API key revoked:** generate a new key, update `APPSTORE_API_PRIVATE_KEY` (secret) + `APPSTORE_API_KEY_ID` (variable).

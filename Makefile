SCHEME     = WardrobeApp
PROJECT    = app/WardrobeApp/WardrobeApp.xcodeproj
PACKAGE    = app/WardrobeApp/WardrobeKit
DEST       = platform=iOS Simulator,name=iPhone 17 Pro
BUNDLE_ID  = com.ayungavis.WardrobeApp
BUILD_LOG  = /tmp/wardrobeapp-build.log
TEST_FLAGS ?=

.DEFAULT_GOAL := help

.PHONY: help validate \
        ios-generate ios-format ios-lint ios-test ios-build ios-run ios-validate \
        backend-up backend-down backend-migrate backend-reset backend-run backend-worker backend-seed-ai backend-openapi \
        backend-fmt backend-lint backend-test backend-build backend-image backend-validate backend-live-ai

## Descriptions come from the `##` comments below, so this list cannot go stale.
help:
	@echo "Wardrobe Challenge App — iOS app (app/) and Rust backend (services/)"
	@echo
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ------------------------------------------------------------------- iOS

ios-generate: ## Regenerate WardrobeApp.xcodeproj from project.yml
	cd app/WardrobeApp && xcodegen generate

ios-format: ## SwiftFormat the whole repo
	swiftformat .

ios-lint: ## SwiftLint in strict mode
	swiftlint --strict

ios-test: ## Unit tests via swift test — no simulator needed
	swift test --package-path $(PACKAGE) $(TEST_FLAGS)

# xcodebuild output is huge — log to a file, print the tail only on failure.
ios-build: ios-generate ## Build for the iPhone simulator
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' build > $(BUILD_LOG) 2>&1 \
		&& grep -E '^\*\* BUILD' $(BUILD_LOG) \
		|| (tail -30 $(BUILD_LOG); exit 1)

ios-run: ios-build ## Build, install, and launch on the booted simulator
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -showBuildSettings 2>/dev/null \
		| awk '$$1 == "BUILT_PRODUCTS_DIR" { print $$3; exit }'); \
	xcrun simctl install booted "$$APP/$(SCHEME).app" && \
	xcrun simctl launch booted $(BUNDLE_ID)

ios-validate: ios-format ios-lint ios-test ios-build ## format → lint → test → build
	@echo "✅ iOS OK — format, lint, test, build semua hijau"

# --------------------------------------------------------------- backend

# Every backend target delegates to services/Makefile, so no command is
# written twice. The .env prerequisite means a fresh clone works on the first
# try instead of failing with an unexplained connection error.
services/.env:
	cp services/.env.example services/.env

backend-up: services/.env ## Start Postgres and MinIO, wait until healthy
	$(MAKE) -C services up

backend-down: ## Stop Postgres and MinIO
	$(MAKE) -C services down

backend-migrate: services/.env ## Apply database migrations
	$(MAKE) -C services migrate

backend-reset: services/.env ## Drop and rebuild the database from empty
	$(MAKE) -C services reset

backend-run: services/.env ## Run the API (Swagger UI at http://localhost:8080/docs)
	$(MAKE) -C services run

backend-worker: services/.env ## Run the job worker against the local containers
	$(MAKE) -C services worker

backend-seed-ai: services/.env ## Enable illustration jobs locally (needs OPENROUTER_TEST_MODEL in .env)
	$(MAKE) -C services seed-ai

backend-openapi: ## Regenerate services/openapi.json from the handlers
	$(MAKE) -C services openapi

backend-fmt: ## cargo fmt
	$(MAKE) -C services fmt

backend-lint: ## cargo clippy -D warnings
	$(MAKE) -C services lint

backend-test: services/.env ## cargo test (starts the containers it needs)
	$(MAKE) -C services test

backend-build: ## cargo build --release for both binaries (what the Dockerfile runs)
	$(MAKE) -C services build

backend-image: ## docker build the deploy image (context is services/, needs a >=4 GiB builder)
	$(MAKE) -C services image

backend-validate: services/.env ## fmt → clippy → test
	$(MAKE) -C services validate
	@echo "✅ backend OK — fmt, clippy, test all green"

backend-live-ai: services/.env ## Call OpenRouter for real (needs a key and credits)
	$(MAKE) -C services live-ai

# ------------------------------------------------------------------- both

validate: ios-validate backend-validate ## Validate both sides. Must pass before every PR.
	@echo "✅ validate OK — iOS dan backend green"

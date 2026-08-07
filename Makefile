SCHEME     = WardrobeApp
PROJECT    = app/WardrobeApp/WardrobeApp.xcodeproj
PACKAGE    = app/WardrobeApp/WardrobeKit
DEST       = platform=iOS Simulator,name=iPhone 17 Pro
BUNDLE_ID  = com.ayungavis.WardrobeApp
BUILD_LOG  = /tmp/wardrobeapp-build.log

.PHONY: generate format lint test build run validate

generate:
	cd app/WardrobeApp && xcodegen generate

format:
	swiftformat .

lint:
	swiftlint --strict

test:
	swift test --package-path $(PACKAGE)

# xcodebuild output is huge — log to a file, print the tail only on failure.
build: generate
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' build > $(BUILD_LOG) 2>&1 \
		&& grep -E '^\*\* BUILD' $(BUILD_LOG) \
		|| (tail -30 $(BUILD_LOG); exit 1)

run: build
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -showBuildSettings 2>/dev/null \
		| awk '$$1 == "BUILT_PRODUCTS_DIR" { print $$3; exit }'); \
	xcrun simctl install booted "$$APP/$(SCHEME).app" && \
	xcrun simctl launch booted $(BUNDLE_ID)

validate: format lint test build
	@echo "✅ validate OK — format, lint, test, build semua hijau"

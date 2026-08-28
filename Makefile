SHELL := /bin/bash

.PHONY: setup build app test test-unit test-ui lint validate-privacy dist clean-dist clean ci

# Resolves the local Swift package graph. There are no external
# dependencies (every dependency is a local path package under Packages/),
# so this never touches the network.
setup:
	swift package resolve

# Builds every target (the App executable and every local package) in
# debug configuration.
build:
	swift build

# Builds and assembles a distributable IPhoneCamLite.app for the given
# VERSION, without requiring VERSION (defaults to a dev build under dist/).
app:
	@version="$(VERSION)"; \
	if [ -z "$$version" ]; then version="0.0.0-dev"; fi; \
	./scripts/package_app.sh "$$version"

# Runs the full test suite (CameraCoreTests, AdapterFixtureTests, UITests).
test:
	swift test

# CameraCoreTests + AdapterFixtureTests only: pure-logic and fixture-based
# tests that never touch AppKit/SwiftUI.
test-unit:
	swift test --filter CameraCoreTests
	swift test --filter AdapterFixtureTests

# UITests: app-owned view-model/flow tests (menu commands, opening
# Settings/Diagnostics/Onboarding, a mocked failure's remediation). These
# are plain XCTest against the app module's view models, not
# XCUIApplication-driven UI automation -- see docs/TESTING.md for why true
# UI-automation tests are tracked as follow-up work rather than included
# here.
test-ui:
	swift test --filter UITests

# Uses swift-format if the toolchain provides it; never requires installing
# a separate formatter/linter, so CI can never fail to install a required
# tool.
lint:
	@if command -v swift-format >/dev/null 2>&1; then \
		echo "Running swift-format lint..."; \
		swift-format lint --recursive App Packages Tests; \
	else \
		echo "swift-format not found on PATH -- skipping (not a required dependency; install Xcode's toolchain to enable this check)."; \
	fi

# Validates Resources/PrivacyInfo.xcprivacy is well-formed. Uses plutil
# when available (macOS/Xcode CLT); falls back to Python's plistlib
# elsewhere so this can still run somewhere useful in development.
validate-privacy:
	@if command -v plutil >/dev/null 2>&1; then \
		plutil -lint Resources/PrivacyInfo.xcprivacy; \
	else \
		python3 -c "import plistlib; plistlib.load(open('Resources/PrivacyInfo.xcprivacy','rb')); print('Resources/PrivacyInfo.xcprivacy: OK (plistlib fallback -- install Xcode Command Line Tools for plutil)')"; \
	fi

# Builds a versioned, distributable release: `make dist VERSION=1.2.3`.
dist:
	@if [ -z "$(VERSION)" ]; then \
		echo "usage: make dist VERSION=<x.y.z>" >&2; \
		exit 1; \
	fi
	./scripts/package_app.sh "$(VERSION)"

clean-dist:
	@repo_root="$(CURDIR)"; \
	if [ -z "$$repo_root" ] || [ "$$repo_root" = "/" ]; then \
		echo "refusing to run: repository root is unset or is '/'" >&2; \
		exit 1; \
	fi; \
	target="$$repo_root/dist"; \
	if [ "$$(basename "$$target")" != "dist" ]; then \
		echo "refusing to remove unexpected path: $$target" >&2; \
		exit 1; \
	fi; \
	if [ -d "$$target" ]; then \
		rm -rf -- "$$target"; \
		echo "removed $$target"; \
	else \
		echo "nothing to clean ($$target does not exist)"; \
	fi

# Removes SwiftPM's build directory in addition to dist/.
clean: clean-dist
	rm -rf .build

# The full CI-equivalent local command: resolve, build, run the fast unit
# and fixture tests, and validate the privacy manifest. (CI additionally
# runs UITests and packages a synthetic release -- see
# .github/workflows/ci.yml.)
ci: setup build test-unit validate-privacy

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Replaced the shell-script-and-AppleScript toolkit with a native macOS
  Swift menu bar app.** The `make zoom`/`make teams` launcher scripts,
  `scripts/check_prereqs.sh`, `scripts/reset_camera_services.sh`,
  `scripts/keepawake.sh`, and the custom `tests/run.sh` test runner are
  removed; their behavior now lives in a SwiftPM package graph
  (`App/`, `Packages/{CameraCore,AppAutomation,SystemChecks,Logging}`)
  with a `MenuBarExtra` UI, Onboarding, Settings, and Diagnostics
  windows. See [docs/MIGRATION.md](docs/MIGRATION.md) for a full mapping
  of every removed file to where its behavior now lives, and
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the new module
  design.
- Device and UI-label configuration moved from environment variables
  read at script invocation time to a typed, persisted Settings store
  edited in the app's Settings window; the same
  empty-value-falls-back-to-default semantics are preserved. See
  [docs/MIGRATION.md](docs/MIGRATION.md#configuration-model-change).
- The Zoom and Teams device-selection AppleScript files
  (`select_zoom_camera.scpt`, `select_teams_camera.scpt`) are kept
  verbatim as a documented transitional automation bridge, now packaged
  as SwiftPM resources and invoked via `Foundation.Process` with a
  discrete argument array (never shell string interpolation) instead of
  being called from a shell script.
- `tests/run.sh` and every `scripts/test_*.sh` file are replaced by
  three SwiftPM test targets (`CameraCoreTests`, `AdapterFixtureTests`,
  `UITests`) run via `swift test` / `make test`; see
  [docs/TESTING.md](docs/TESTING.md).
- Rewrote the Makefile (`build`, `app`, `test`, `test-unit`, `test-ui`,
  `lint`, `validate-privacy`, `dist`, `clean-dist`, `clean`, `ci`) and
  `.github/workflows/ci.yml`/`.github/workflows/release.yml` to build and
  test the native app instead of linting/running shell scripts.
- `scripts/build_release.sh` is replaced by `scripts/package_app.sh`,
  which assembles a `.app` bundle from a `swift build -c release` output
  instead of archiving the shell scripts.

### Added

- A `MenuBarExtra`-based menu bar app with live selection status,
  one-click Zoom/Teams device selection, and a native keep-awake toggle
  (`ProcessInfo` activity assertions, replacing `caffeinate`).
- An Onboarding flow that checks Accessibility and Apple Events
  permission state without a shell-based prerequisite check, and never
  reports a permission as granted when it isn't.
- A read-only Diagnostics window covering the same prerequisite checks
  `scripts/check_prereqs.sh` used to perform (Wi-Fi, Bluetooth, macOS
  version, installed applications, permissions), plus a
  camera-service-reset action behind an injectable protocol.
- `docs/ARCHITECTURE.md`, `docs/TESTING.md`, and `docs/MIGRATION.md`.
- `Resources/PrivacyInfo.xcprivacy` and app icon assets
  (`Resources/Assets.xcassets`) for the packaged `.app`.

### Fixed

- N/A for this release — the reliability fixes below (from the
  since-removed shell/AppleScript implementation) are preserved in
  behavior by the native implementation's typed `SelectionError` cases
  and fixture tests (see `docs/ARCHITECTURE.md` and `docs/TESTING.md`),
  rather than re-listed here as new fixes.

## [0.1.2] - 2025-09-17

### Added

- Zoom camera selection support (`scripts/select_zoom_camera.scpt`), so `make zoom` can automatically select the configured camera in Zoom's video settings.

## [0.1.1] - 2025-09-17

### Added

- `scripts/keepawake.sh` and a `make keepawake` target to prevent macOS from sleeping during long calls.

## [0.1.0] - 2025-09-17

### Added

- Initial usable version of the project, including `scripts/reset_camera_services.sh` and a `make reset-camera` target to restart the camera/media agents when a camera stops responding.

[Unreleased]: https://github.com/bubnicbf/iphone-cam-lite/compare/v0.1.2...dev
[0.1.2]: https://github.com/bubnicbf/iphone-cam-lite/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/bubnicbf/iphone-cam-lite/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/bubnicbf/iphone-cam-lite/releases/tag/v0.1.0

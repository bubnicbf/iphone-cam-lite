# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- An automated Bash test suite (`tests/run.sh` plus `scripts/test_*.sh`) covering the Makefile, prerequisite checks, the Zoom/Teams launchers, camera/microphone selection, post-selection verification, and safe restart of camera services.
- A `scripts/build_release.sh` packaging script that produces reproducible `tar.gz` and `zip` release archives plus a `SHA256SUMS.txt` checksum file, along with a matching regression test (`scripts/test_build_release.sh`).
- `make test`, `make lint`, `make dist`, and `make clean-dist` targets.
- GitHub Actions workflows for continuous integration (`.github/workflows/ci.yml`) and tag-triggered release packaging (`.github/workflows/release.yml`).
- `CONTRIBUTING.md` describing how to set up, test, and submit changes.
- `SECURITY.md` describing how to report a vulnerability.

### Fixed

- Hardened the Zoom and Teams device-selection automation against several real-world failure modes: it now verifies the camera/microphone selection actually took effect instead of assuming a click succeeded, reports AppleScript automation failures instead of failing silently, and works correctly with localized (non-English) menu UIs.
- Made the camera and microphone device names configurable instead of hardcoded.
- Fixed the launcher scripts to resolve bundled resources (AppleScript files) relative to the script's own location rather than the caller's current directory, and to match the launched application's process exactly instead of matching on a loose name pattern.
- Fixed application-launch handling to report a timeout instead of hanging indefinitely.
- Fixed prerequisite checks to detect the active Wi-Fi interface correctly, avoid a false positive from an obsolete `airport` check, and avoid a false positive from Bluetooth detection.
- Fixed the Makefile so it parses cleanly (removed stray Markdown code-fence characters) and so the scripts it invokes keep their executable permissions under version control.

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

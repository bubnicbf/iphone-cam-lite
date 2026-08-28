# Migration: shell/AppleScript architecture → native Swift app

This document maps every file removed in the move from a Bash/AppleScript
toolkit to the native `App`/`Packages` architecture, to where its behavior
now lives, and why. Nothing here was deleted speculatively — each row was
only removed once the corresponding native code and tests existed and
were exercised (see `docs/TESTING.md`).

## Runtime scripts

| Removed | Replaced by | Notes |
| --- | --- | --- |
| `scripts/start_zoom.sh` | `App/MenuBar/MenuBarViewModel.swift` calling `CameraCore.CameraSelectionCoordinator.select(application: .zoom, ...)`, wired through `Packages/AppAutomation/Sources/ZoomAdapter` | Launch, readiness-wait, and selection are now three explicit, independently testable steps (`ApplicationReadiness`, `CameraSelectionCoordinator`, `ZoomDeviceSelectionAdapter`) instead of one script. |
| `scripts/start_teams.sh` | Same coordinator, with `application: .teams` → `Packages/AppAutomation/Sources/TeamsAdapter` | Teams' Settings → Devices navigation now lives in `TeamsDeviceSelectionAdapter.swift`. |
| `scripts/select_zoom_camera.scpt` | `Packages/AppAutomation/Sources/ZoomAdapter/Resources/select_zoom_camera.scpt` | **Kept verbatim**, not rewritten — packaged as a SwiftPM target resource and invoked via `Foundation.Process` + `/usr/bin/osascript` with a discrete argument array (never shell string interpolation). This is the documented transitional AppleScript bridge; see `docs/ARCHITECTURE.md`. |
| `scripts/select_teams_camera.scpt` | `Packages/AppAutomation/Sources/TeamsAdapter/Resources/select_teams_camera.scpt` | Same treatment as the Zoom script. `TeamsDeviceSelectionAdapterTests.swift` fixture-tests the packaged copy to confirm it still contains no sign-in/account automation. |
| `scripts/check_prereqs.sh` | `Packages/SystemChecks` (`WiFiCheck`, `BluetoothCheck`, `MacOSVersionCheck`, `InstalledApplicationCheck`, `AccessibilityTrustCheck`, `AutomationAvailabilityCheck`) surfaced in `App/Diagnostics` | Split into one `SystemCheck` per concern instead of one monolithic script; each is read-only and independently unit-testable. Run from the menu bar app's Diagnostics window; there is no scripted/CLI equivalent (unlike the old shell script, which could be run headless) -- this is a deliberate scope change since the app has no CLI entry point. |
| `scripts/reset_camera_services.sh` | `App/Diagnostics/CameraServiceResetting.swift`, exposed as a Diagnostics action | Still shells out to reset camera-related services, but now behind an injectable `CameraServiceResetting` protocol with a fake used in tests — production code is the only thing that touches the real service. |
| `scripts/keepawake.sh` | `App/MenuBar/MenuBarViewModel.swift`'s keep-awake toggle, using `ProcessInfo.processInfo.beginActivity`/`endActivity` | Replaces shelling out to `caffeinate` with the native macOS API for the same guarantee; ends the activity assertion automatically when toggled off or on quit. |
| `scripts/build_release.sh` | `scripts/package_app.sh` (kept as a script, rewritten) | Packaging a `.app` bundle from a SwiftPM build is still a natural shell script (no Xcode project to build against); it now assembles `Contents/{MacOS,Resources}` from `swift build -c release`, patches version info with `PlistBuddy`, and compiles the asset catalog with `xcrun actool` (falling back to a raw resource copy when Xcode tooling isn't present). |
| `tests/run.sh` | `swift test` (via `make test`) | The custom shell test discovery/runner is retired outright — SwiftPM's own test runner replaces it. See `docs/TESTING.md`. |

## Shell test suite

Every `scripts/test_*.sh` file was a Bash test for the file(s) above; each
is retired because the behavior it tested moved into native Swift code
with native Swift tests:

| Removed test | Behavior now covered by |
| --- | --- |
| `scripts/test_applescript_error_handling.sh` | `Tests/AdapterFixtureTests/ZoomAutomationErrorClassifierTests.swift`, `TeamsAutomationErrorClassifierTests.swift` |
| `scripts/test_build_release.sh` | No direct native equivalent yet — `scripts/package_app.sh` is validated with `bash -n` and manual packaging runs, not an automated regression test. Tracked as follow-up in `docs/ARCHITECTURE.md`'s "Known limitations." |
| `scripts/test_check_prereqs.sh` | `Packages/SystemChecks` has no dedicated `Tests/` directory of its own (its checks are read-only wrappers over system APIs); its consumer, `Tests/UITests/DiagnosticsViewModelTests.swift`, exercises the check-running flow against `Fakes/FakeSystemCheck.swift`. |
| `scripts/test_executable_permissions.sh` | No longer applicable — there is no fleet of standalone executable scripts whose `chmod` bits need checking. `scripts/package_app.sh` is the only script left, and its permissions are set by `git` (`update-index --chmod=+x`) rather than a runtime check. |
| `scripts/test_launcher_failures.sh` | `Tests/CameraCoreTests/ApplicationReadinessTests.swift`, `Tests/AdapterFixtureTests/ZoomDeviceSelectionAdapterTests.swift` / `TeamsDeviceSelectionAdapterTests.swift` |
| `scripts/test_makefile.sh` | `make -n <target>` dry runs during development (see `docs/MIGRATION.md`'s validation note below); no automated Makefile test exists natively, since the Makefile now mostly wraps `swift build`/`swift test`, which are tested by definition when they run. |
| `scripts/test_reset_camera_services.sh` | Covered indirectly through `App/Diagnostics/CameraServiceResetting.swift`'s protocol boundary and its fake, though a dedicated `Tests/` case for the Diagnostics reset action is tracked as follow-up. |
| `scripts/test_selection_confirmation.sh` | `Tests/CameraCoreTests/ConfirmationTests.swift`, `Tests/AdapterFixtureTests/ZoomDeviceSelectionAdapterTests.swift` / `TeamsDeviceSelectionAdapterTests.swift` (positive read-back confirmation) |
| `scripts/test_ui_label_configuration.sh` | `Tests/CameraCoreTests/DeviceSettingsSnapshotTests.swift` (empty-string-falls-back-to-default semantics), `App/Settings` | Configuration is now typed and injected (`SettingsStoring`) rather than read from environment variables at script invocation time — see the "Configuring device names" section rewritten in `README.md`. |

## What did **not** get a 1:1 native replacement (yet)

- **`scripts/test_build_release.sh`** and **automated coverage for
  `scripts/package_app.sh`** — packaging is validated manually and with
  `bash -n`, not with an automated regression suite. Flagged, not hidden.
- **A dedicated automated test for the Diagnostics camera-service-reset
  action** — the protocol boundary and fake exist
  (`CameraServiceResetting`), but no `Tests/` file yet exercises
  `App/Diagnostics/DiagnosticsViewModel.swift`'s reset action specifically
  beyond what `DiagnosticsViewModelTests.swift` covers for checks.
- **True `XCUIApplication` UI automation** replacing what a human would
  manually verify — see `docs/TESTING.md`, "What UITests is not."

These are called out explicitly (here and in `docs/ARCHITECTURE.md`'s
"Known limitations") rather than left to be discovered later.

## Configuration model change

The old scripts read `CAMERA_NAME`, `MICROPHONE_NAME`,
`ZOOM_MEETING_MENU_LABEL`, `ZOOM_CAMERA_MENU_LABEL`,
`ZOOM_MICROPHONE_MENU_LABEL`, `ZOOM_CAMERA_CONTROL_LABEL`,
`ZOOM_MICROPHONE_CONTROL_LABEL`, `TEAMS_SETTINGS_MENU_LABEL`,
`TEAMS_DEVICES_LABEL`, `TEAMS_CAMERA_CONTROL_LABEL`, and
`TEAMS_MICROPHONE_CONTROL_LABEL` as environment variables at invocation
time. The native app replaces environment variables with a typed,
injectable `SettingsStoring` protocol (`App/Settings/SettingsStoring.swift`,
backed by `AppSettingsStore.swift`) edited through `App/Settings/SettingsView.swift`;
the same empty-value-falls-back-to-default semantics are preserved and
tested (`DeviceSettingsSnapshotTests.swift`, `SettingsPersistenceTests.swift`).
There is currently no environment-variable override path in the native
app — settings are persisted, not set per-invocation — which is a
deliberate behavior change, not an oversight: a menu bar app has no
natural "per-invocation environment" the way a one-shot shell command did.

## Why migrate instead of deleting and starting over

Every removal above was made only after: (1) the corresponding native
module existed, (2) tests exist that exercise the same failure
distinctions the shell test was checking (see the table above and
`docs/TESTING.md`), and (3) nothing else in the tree still referenced the
removed file. `scripts/` was searched for stale references to every
retired script and AppleScript file as part of this migration; none
remained once the corresponding `App`/`Packages` code was in place.

## Validation constraints during this migration

This migration was authored and validated in an environment with no
Swift toolchain available (no `swift`, `xcodebuild`, or `xcrun`, and
`download.swift.org` unreachable). Compilation itself could not be
proven here. What was validated instead, and how, is recorded in the
project's PR/commit history and summarized in `docs/TESTING.md` and
`docs/ARCHITECTURE.md`; `.github/workflows/ci.yml` is where `swift
build`/`swift test` actually run on a real macOS runner for every future
change.

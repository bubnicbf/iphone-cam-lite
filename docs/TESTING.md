# Testing

This project's automated tests are ordinary SwiftPM test targets. There is
no shell test runner and no `tests/run.sh` anymore — `swift test` (or the
`make` targets that wrap it) is the only test entry point.

## Running the tests

From a fresh clone, with a macOS Swift toolchain installed (Xcode 15+ /
Swift 5.9+, macOS 13 Ventura or newer):

```sh
swift build          # resolve the local package graph and build everything
swift test            # run every test target
```

Or via the Makefile:

```sh
make build        # swift build
make test         # runs both test suites below
make test-unit     # CameraCoreTests + AdapterFixtureTests only
make test-ui       # UITests only (view-model tests, still headless — see below)
```

`swift test --list-tests` lists every discovered test without running it;
CI uses this to fail loudly if a target silently stops registering tests
(for example because of a build configuration mistake) rather than passing
with zero tests run.

To run a single test target directly:

```sh
swift test --filter CameraCoreTests
swift test --filter AdapterFixtureTests
swift test --filter UITests
```

## What each test target covers

### `Tests/CameraCoreTests`

Tests the pure domain layer in `Packages/CameraCore` — no process
execution, no AppleScript, no real system state. Everything here runs
against fakes (`Fakes/FakeDeviceSelectionAdapter.swift`,
`Fakes/FakeProcessAvailabilityChecking.swift`) and deterministic,
injectable time (`Clock`), never a real clock or a real sleep.

- `CameraSelectionCoordinatorTests.swift` — the coordinator resolves the
  correct adapter for `MeetingApplication.zoom`/`.teams` via
  `AdapterRegistryTests.swift`, propagates a `SelectionError` unchanged,
  wraps a `CancellationError` as `SelectionError.cancelled`, and wraps any
  other thrown error as `.unclassified`. Logging calls are asserted via
  `Logging`'s `TestCaptureLogger`.
- `ApplicationReadinessTests.swift` — bounded, cancellation-aware polling
  for "has the target process appeared" using `FakeProcessAvailabilityChecking`
  and a fake clock: covers appears-immediately, appears-after-N-polls,
  never-appears-within-timeout (→ `.processNeverAppeared` /
  `.applicationStartupTimeout`), and mid-poll cancellation (→
  `CancellationError`, never silently swallowed).
- `ConfirmationTests.swift` — the pure polling primitives
  (`pollUntilValueMatches`, `pollUntilFlagIsTrue`, `isAlreadySelected`) in
  `Confirmation.swift`: matches immediately, matches after N polls, times
  out and reports the last-observed value, and respects cancellation. See
  `docs/ARCHITECTURE.md` for why these are tested even though no adapter
  calls them yet.
- `DeviceNameTests.swift` — `DeviceName` equality/matching is exact after
  trimming leading/trailing whitespace only, never a substring or
  case-insensitive match.
- `DeviceSettingsSnapshotTests.swift` — an empty/unset camera or
  microphone name falls back to the documented default independently of
  the other field; a non-empty value always overrides its default.
- `RetryPolicyTests.swift` — bounded attempt counts and backoff
  computation; there is no unbounded retry path to test because there is
  no unbounded retry path in production code.

### `Tests/AdapterFixtureTests`

Tests `Packages/AppAutomation` (`AppAutomationCore`, `ZoomAdapter`,
`TeamsAdapter`) against fakes
(`Fakes/FakeApplicationLauncher.swift`, `Fakes/FakeProcessProbe.swift`,
`Fakes/FakeAccessibilityAutomationRunner.swift`) and fixed strings, not a
live Zoom/Teams install or a real `osascript` invocation.

- `ZoomAutomationErrorClassifierTests.swift` /
  `TeamsAutomationErrorClassifierTests.swift` — feed real, recorded
  AppleScript error strings (including combined "camera ...; microphone
  ..." failures) through `classify()` and assert the exact resulting
  `SelectionError` case and associated device/reason text. This is where
  the item-not-found vs. click-failed vs. value-unchanged vs.
  wrong-device vs. unreadable-state vs. confirmation-timeout vs.
  ambiguous-match distinctions are locked in as regression tests.
- `ZoomDeviceSelectionAdapterTests.swift` /
  `TeamsDeviceSelectionAdapterTests.swift` — drive the adapters end to end
  against the fakes: exact process-name matching (never a loose/substring
  match), independent camera/microphone selection (one can succeed while
  the other fails, surfaced as `SelectionError.partialSelection`),
  positive read-back confirmation before reporting success, and — for
  Teams specifically — a fixture assertion that the packaged
  `select_teams_camera.scpt` (inspected via the adapter's public
  `defaultScriptURL`) contains no sign-in, account-picker, or credential
  automation of any kind. No test in this target launches a real
  application, restarts a real system service, or requires network
  access.

### `Tests/UITests`

Tests the `App` target's `@MainActor` view models in isolation from
SwiftUI rendering and from AppKit — these are logic tests for
`ObservableObject` state machines, not `XCUIApplication` UI-automation
tests (see "What UITests is not," below).

- `MenuBarViewModelTests.swift` — status transitions
  (idle → selecting → success/failure), that `cancelCurrentSelection()`
  actually cancels the in-flight `Task`, and the keep-awake toggle against
  a fake activity-assertion boundary.
- `OnboardingViewModelTests.swift` — permission-check state reflects
  exactly what the injected `AccessibilityTrustChecking` fake reports, and
  never reports a permission as granted when the fake reports it denied
  (see `docs/ARCHITECTURE.md`'s note on never falsely claiming a grant).
- `DiagnosticsViewModelTests.swift` — running diagnostics against
  `Fakes/FakeSystemCheck.swift` produces the expected `SystemCheckResult`
  list and never mutates any injected fake's state (diagnostics are
  read-only by contract).
- `SettingsPersistenceTests.swift` — round-trips settings through an
  in-memory `SettingsStoring` fake, including the empty-string-falls-back
  semantics also covered by `DeviceSettingsSnapshotTests.swift`, this time
  through the `AppSettingsStore` layer.

### What `UITests` is not

This target does not launch the built app, drive real windows, or use
`XCUIApplication`. Doing that reliably from CI (and from this
environment) requires a signed/runnable app bundle, a rendering session,
and Accessibility permission granted to the CI runner — none of which
this project currently sets up. `.github/workflows/ci.yml` documents this
gap explicitly with a `ui-automation-smoke` job stub gated behind
`if: false`, rather than silently having no UI-automation story at all.
Building real `XCUIApplication` coverage is tracked as follow-up (see
`docs/ARCHITECTURE.md`, "Known limitations").

## What "hermetic" means for this suite

No test in `Tests/` does any of the following:

- Launches a real Zoom, Teams, or other external application.
- Calls `/usr/bin/osascript` or executes a real AppleScript file.
- Restarts, resets, or otherwise touches a real system service (camera
  daemon, `cfprefsd`, etc.).
- Reads or writes real `UserDefaults`/real user preference files.
- Requires network access.
- Depends on wall-clock time — every timeout/poll-based test injects a
  fake `Clock`/`Sleeping` implementation and advances it deterministically.

Every external boundary (`ApplicationLauncher`, `ProcessProbe`,
`AccessibilityAutomationRunner`, `SettingsStoring`, `SystemCheck`,
`AccessibilityTrustChecking`, `CameraServiceResetting`, `Sleeping`,
`ProcessAvailabilityChecking`) has a paired fake specifically so this
holds. If a change to production code requires a test to reach outside
the process to pass, that is a design smell, not something to work around
with `#if os(macOS)` guards or a "run manually" note.

## Linting

```sh
make lint
```

Runs `swift build` with warnings-as-errors where practical and validates
the privacy manifest (see below). There is no `shellcheck`/`osacompile`
step anymore — the only scripts left in `scripts/` are Bash
(`scripts/package_app.sh`, syntax-checked with `bash -n`) rather than
runtime AppleScript.

## Validating the privacy manifest

```sh
make validate-privacy
```

Confirms `Resources/PrivacyInfo.xcprivacy` is well-formed plist and
declares the expected required-reason API category. On a machine without
`plutil` (this includes the environment this migration was authored and
tested in — see `docs/MIGRATION.md`), this falls back to a Python
`plistlib` parse that checks the same structure.

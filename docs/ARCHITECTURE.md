# Architecture

IPhoneCamLite is a native macOS menu bar application built with Swift,
SwiftUI, and local Swift packages. This document explains the module
boundaries, the dependency direction between them, why a transitional
AppleScript bridge still exists, what permissions the app requests and
why, and how device names and localized UI labels are configured.

If you're looking for the previous shell-script-based implementation, see
[MIGRATION.md](MIGRATION.md) for what was removed, what was kept, and
where each old behavior now lives.

## Why a Swift package graph instead of an Xcode project

The repository builds as a root Swift package (`Package.swift`) plus four
local packages under `Packages/`. This was chosen over a committed
`.xcodeproj`/`.xcworkspace` because it:

- builds reproducibly from a fresh clone with `swift build`/`swift test`,
  with no external dependencies to fetch (every dependency is a local path
  package) and no committed derived state (`.build/`, `.swiftpm/`, and
  Xcode user state are all gitignored);
- needs no globally installed third-party project generator (no XcodeGen,
  no Tuli, no Ruby/Node toolchain) -- `swift build` alone is enough;
- still opens and runs directly in Xcode (`File > Open...` on
  `Package.swift`) for anyone who wants the IDE experience, with the exact
  same module graph;
- keeps the requested top-level layout (`App/`, `Packages/`, `Tests/`,
  `Resources/`) as the actual source of truth, rather than an Xcode
  project's own internal group structure that can drift from the
  filesystem.

`scripts/package_app.sh` assembles the actual `.app` bundle (Info.plist,
`PrivacyInfo.xcprivacy`, compiled asset catalog) around the `swift build`
output for local distribution and CI; see that script and
[TESTING.md](TESTING.md) for what it does and does not require Xcode for.

## Module map and dependency direction

```
App/ (executable target "IPhoneCamLite")
 ├─ MenuBar, Onboarding, Settings, Diagnostics   (SwiftUI + view models)
 └─ AppEnvironment                                (composition root)
      │
      ├──> Packages/CameraCore        (domain layer)
      ├──> Packages/AppAutomation
      │      ├─ AppAutomationCore     ──> CameraCore
      │      ├─ ZoomAdapter           ──> AppAutomationCore, CameraCore
      │      └─ TeamsAdapter          ──> AppAutomationCore, CameraCore
      ├──> Packages/SystemChecks      ──> Logging
      └──> Packages/Logging           (no dependencies)
```

Dependencies only point downward. `CameraCore` depends on nothing but
`Logging`: no SwiftUI, no AppKit, no concrete Zoom/Teams accessibility
detail, and no direct process execution, exactly as required. It defines
protocols (`DeviceSelectionAdapter`, `ProcessAvailabilityChecking`,
`Sleeping`) that the layers below implement, and pure orchestration logic
(`CameraSelectionCoordinator`, `AdapterRegistry`, `ApplicationReadiness`,
`Confirmation`) that is fully unit-testable with fakes.

`AppAutomation` is one Swift package with three targets/products
(`AppAutomationCore`, `ZoomAdapter`, `TeamsAdapter`) so the shared
automation infrastructure (launching an app, checking for an exact
process name, running the Accessibility/AppleScript bridge) is written
once and reused by both application-specific adapters, while each
adapter's Zoom- or Teams-specific behavior stays isolated in its own
target.

`SystemChecks` and `Logging` are siblings with no knowledge of automation
or the UI; `App/` is the only place that wires everything together
(`App/AppEnvironment.swift`), which is what keeps persistence and
automation injectable instead of scattered across the app.

## Why app-specific Accessibility automation remains necessary

macOS has no supported public API for a third-party app to set which
camera or microphone Zoom or Microsoft Teams uses internally -- that
selection lives entirely inside each application's own UI and private
state. `CameraCore` never claims otherwise: `DeviceSelectionAdapter`
implementations drive the target application's own menus and controls via
Accessibility (`System Events`/Apple Events), the same mechanism the
project's original shell/AppleScript implementation used, and then
positively read back the resulting selection before reporting success.
There is no direct AVFoundation call anywhere in this app that "selects"
a camera in Zoom or Teams, because no such call exists.

## The transitional AppleScript bridge

`ZoomAdapter` and `TeamsAdapter` package the project's original,
extensively hardened AppleScript selectors
(`select_zoom_camera.scpt`/`select_teams_camera.scpt`) as SwiftPM target
resources (`Packages/AppAutomation/Sources/{ZoomAdapter,TeamsAdapter}/Resources/`),
rather than rewriting their accessibility-tree search, click-and-verify,
and confirmation-polling logic in Swift for this P0. Two things changed
in how they're invoked, both fixing real bugs the old shell wrapper had:

1. **Resource resolution.** The scripts are now located via SwiftPM's
   generated `Bundle.module`, not a path derived from `$0`/`BASH_SOURCE`.
   This means the packaged `.app` finds them correctly regardless of the
   current working directory the app happens to be launched from --
   something the original `scripts/start_zoom.sh`/`start_teams.sh` had to
   work around manually and imperfectly.
2. **Argument passing.** `AppAutomationCore.OsascriptAutomationRunner` invokes
   `/usr/bin/osascript` via `Foundation.Process` with an explicit
   `arguments: [String]` array -- never a shell command string, `eval`, or
   string interpolation -- so camera/microphone names and UI labels
   containing spaces, apostrophes, parentheses, or Unicode reach the
   script byte-for-byte intact, exactly as the original scripts already
   guaranteed, just via a safer call site.

Everything above that boundary is pure, native Swift:
`ZoomAutomationErrorClassifier`/`TeamsAutomationErrorClassifier` parse the
AppleScript's raised error text into `CameraCore.SelectionError` cases
(see below), and `Confirmation`/`ApplicationReadiness` in `CameraCore`
provide bounded, cancellation-aware polling primitives, independently
unit-tested, that a future pure-Accessibility-API (`AXUIElement`-based)
adapter can adopt to retire the AppleScript bridge entirely without
touching `CameraCore` or the App layer. **That pure-Swift adapter does not
exist yet** -- `ZoomAdapter`/`TeamsAdapter` still delegate the actual
click-and-confirm loop to the packaged AppleScript today. This is the one
place in the codebase where "transitional" is a concrete, tracked TODO
rather than a permanent design.

Text-based error classification is inherently best-effort: it is only as
good as the fixture coverage in `AdapterFixtureTests`. A future Zoom or
Teams release that changes these message shapes could produce a
`SelectionError.unclassified` where a more specific case used to apply --
the underlying message is preserved either way, never discarded.

## What permissions the app requests, and why

- **Accessibility** (`System Settings > Privacy & Security >
  Accessibility`): required for `System Events` to read and click Zoom's
  and Teams' menus/controls on the app's behalf. Checked read-only via
  `SystemChecks.AccessibilityTrustCheck` (backed by
  `AXIsProcessTrustedWithOptions(nil)`, which never shows a prompt itself)
  and explained in `App/Onboarding`, which links directly to the
  Accessibility settings pane. The app **never** claims this permission is
  granted except when a fresh, positive read reports it.
- **Apple Events / automation** (per-target prompts for "System Events",
  Zoom, and Microsoft Teams): required to send the Apple Events that
  `/usr/bin/osascript` uses. Declared via `NSAppleEventsUsageDescription`
  in `Resources/Info.plist`. The app is not sandboxed for this P0 (see
  "Known limitations" in MIGRATION.md), so no
  `com.apple.security.automation.apple-events` entitlement is required for
  local, unsigned debug builds.

No camera or microphone usage description is declared, because this app
never captures a camera or microphone stream itself -- it only drives
Zoom's/Teams' own device-selection UI. Adding
`NSCameraUsageDescription`/`NSMicrophoneUsageDescription` would misrepresent
what the app does.

## Teams authentication is never automated

`TeamsAdapter` requires the current ("new") Teams client to already be
signed in and fully loaded. Neither the packaged AppleScript nor any Swift
code in this repository clicks a sign-in button, enters credentials, or
interacts with an account picker. If Teams is signed out or still
loading, the automation simply cannot find the Devices entry point and
this surfaces as `SelectionError.settingsUIUnavailable` --
`TeamsAutomationErrorClassifierTests.testTeamsSignedOutOrNotReadyNeverAttemptsAuthentication`
locks in both the classification and a direct scan of the packaged script
for credential/account-picker references.

The legacy ("classic") Teams client is intentionally unsupported: its
process name and Settings UI both differ from the new client's, and
`TeamsDeviceSelectionAdapter` matches only the new client's exact process
name (`MSTeams`), never a substring that could also match the legacy
client's `Teams` executable.

## How device names and localized UI labels are configured

`CameraCore.DeviceSettingsSnapshot` (camera/microphone names) and
`ZoomUILabels`/`TeamsUILabels` (per-application menu/control label
overrides) each resolve an empty-or-unset override to a documented
default -- the same `"${VAR:-default}"` rule the original shell scripts
used, now expressed once as `resolvedOrDefault(_:default:)` instead of
duplicated per script. `App/Settings/AppSettingsStore` is the single typed,
`@MainActor`-observable, injectable-persistence surface that reads and
writes these values (via `SettingsStoring`, backed by `UserDefaults` in
production and an in-memory store in tests/previews) and builds a fresh
`DeviceSettingsSnapshot` for each selection request. `CameraSelectionCoordinator`
never reads persistence directly.

Matching is always exact after trimming only leading/trailing whitespace
(`CameraCore.DeviceName`) -- never a substring match, never
case-insensitive -- preserving the original scripts' documented behavior
byte-for-byte.

## How both device selections are verified

`DeviceSelectionAdapter.selectDevices(using:)` returns a
`DeviceSelectionSuccess` (both a confirmed camera and a confirmed
microphone) or throws a `SelectionError` -- there is no partially
populated success value. When the packaged AppleScript reports that only
one of the two devices was confirmed, the classifier maps that into
`SelectionError.partialSelection(cameraFailure:microphoneFailure:)` with
the failing side's specific reason attached, rather than a single generic
failure that would hide which device actually failed and why.

## Logging

`Packages/Logging` wraps Apple's unified logging (`os.Logger`) behind the
`AppLogging` protocol, with one subsystem
(`com.iphonecamlite.app`) and a category per functional area
(`app`, `automation`, `adapters`, `diagnostics`, `systemChecks`).
Device names and other potentially personal values are logged at `.debug`
level with `privacy: .private`, so they're redacted by default and never
appear in the standard log stream. `TestCaptureLogger` gives unit tests an
observable, synchronous stand-in.

## Known limitations

- The AppleScript bridge described above is the one non-Swift-native
  piece of the runtime architecture. It is packaged reliably and invoked
  safely, but it is still UI/accessibility scripting, not an official
  vendor API, and a large enough Zoom/Teams UI change could still require
  an updated selector or label override.
- The app is unsigned and not notarized for this P0 (see MIGRATION.md);
  first launch requires the standard Gatekeeper right-click-Open flow.
- True `XCUIApplication`-driven UI automation of the live menu bar app is
  not implemented; see [TESTING.md](TESTING.md) for what `Tests/UITests`
  covers instead and why.

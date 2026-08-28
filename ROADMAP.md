# iPhone Cam Lite — Roadmap

A high-level plan for growing the project from a shell/AppleScript
toolkit -> native Swift menu bar app -> ecosystem tooling.

---

## Done (v0.3.0 — Native Swift Menu Bar App)
**Goal:** Replace the shell-script-and-AppleScript toolkit with a native,
modular macOS app.

- [x] **Native menu bar app** — `MenuBarExtra` UI with live selection
  status, one-click Zoom/Teams device selection, and a keep-awake toggle
  (`App/MenuBar`).
- [x] **Onboarding** — explains and checks Accessibility/Apple Events
  permissions without ever claiming a false grant (`App/Onboarding`).
- [x] **Diagnostics** — read-only prerequisite checks (Wi-Fi, Bluetooth,
  macOS version, installed apps, permissions) plus a manual
  camera-service-reset action (`App/Diagnostics`, `Packages/SystemChecks`).
- [x] **Typed, persisted Settings** — device names and menu/control label
  overrides, replacing environment-variable configuration
  (`App/Settings`).
- [x] **`CameraCore` domain layer** — pure Swift package with a typed
  `SelectionError` taxonomy (launch failure, startup timeout,
  process-never-appeared, settings UI unopenable, control not found,
  ambiguous match, action failed, value unchanged, wrong device selected,
  state unreadable, confirmation timeout, partial selection) so failure
  distinctions the old scripts made in prose are now compiler-checked
  types.
- [x] **`AppAutomation` adapters** — Zoom and Teams device selection
  behind injectable protocols, preserving exact process-name matching,
  independent camera/mic selection, and positive read-back confirmation;
  the existing hardened AppleScript files are kept as a documented
  transitional bridge rather than rewritten from scratch (see
  `docs/ARCHITECTURE.md`).
- [x] **Hermetic test suite** — `CameraCoreTests`, `AdapterFixtureTests`,
  `UITests` running via `swift test`, with no real app launches, service
  restarts, or network dependency (see `docs/TESTING.md`).
- [x] **CI on SwiftPM** — `.github/workflows/ci.yml` builds and tests the
  native app on macOS runners; `.github/workflows/release.yml` packages
  the native `.app` instead of archiving shell scripts.
- [x] **Migration docs** — `docs/ARCHITECTURE.md`, `docs/MIGRATION.md`
  mapping every retired script to its native replacement.

See [docs/MIGRATION.md](docs/MIGRATION.md) for the full script-by-script
mapping and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the module
design and known limitations (the AppleScript bridge is transitional; the
app is unsigned/not notarized for this release; there is no true
`XCUIApplication` UI-automation coverage yet).

---

## Next (v0.4.0 — Native Accessibility Automation)
**Goal:** Retire the transitional AppleScript bridge in favor of a
pure-Swift Accessibility (AXUIElement) implementation.

- [ ] **Pure-Swift device-selection adapter**
  - Reuse the already-built-and-tested `Confirmation`/`ApplicationReadiness`
    primitives in `CameraCore` (currently exercised by tests but not yet
    wired into production adapters)
  - Replace `osascript` invocation of `select_zoom_camera.scpt` /
    `select_teams_camera.scpt` with direct `AXUIElement` calls
  - Keep the same `SelectionError` taxonomy and confirmation guarantees
- [ ] **`XCUIApplication` UI automation**
  - Real end-to-end UI tests replacing the `if: false`-gated
    `ui-automation-smoke` CI job stub
- [ ] **Automated packaging regression test**
  - Cover `scripts/package_app.sh` with an automated check rather than
    manual verification
- [ ] **Signing and notarization**
  - Distribute a signed, notarized build to avoid Gatekeeper prompts

---

## Future (v0.5.0 — Ecosystem & Packaging)
**Goal:** Expand reach, simplify installs, and support more apps.

- [ ] **Packaging**
  - Publish official Homebrew formula
- [ ] **More app support**
  - Google Meet (browser-based settings automation)
  - Webex (device selection parity with Zoom/Teams)

---

## Backlog / Stretch Ideas
**Goal:** Advanced or experimental features for power users.

- OBS integration with VirtualCam + scene presets
- NDI/Syphon bridge for pro video workflows
- Global hotkeys (via Hammerspoon) to toggle cam/mic
- Remote control API (local HTTP server for scripting)
- AI enhancements (background blur, auto-framing, face tracking)

---

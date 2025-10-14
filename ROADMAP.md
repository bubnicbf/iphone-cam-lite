# iPhone Cam Lite — Roadmap

A high-level plan for growing the project from shell scripts -> Swift CLI -> menu bar app -> ecosystem tooling.

---

## Current (v0.2.0 — Hardening & Reliability)
**Goal:** Make the AppleScript + shell approach stable for daily use.

- [ ] **Robust device selection**
  - Retry/backoff if Zoom/Teams UI not ready
  - Fail gracefully with clear error messages
- [ ] **Configurable device names**
  - Store `camera_name` and `mic_name` in `config/devices.yml`
- [ ] **Structured logging**
  - Write logs to `logs/{zoom,teams}.log`
  - Add `make logs` target
- [ ] **Tooling improvements**
  - GitHub Actions CI: run `shellcheck`, `osacompile`, and `markdownlint`
  - Makefile targets: `zoom`, `teams`, `reset-camera`, `logs`, `check`
- [ ] **Documentation**
  - Add `docs/TROUBLESHOOTING.md` with privacy/permissions setup
- [ ] **Optional LaunchAgent**
  - Auto-select iPhone Camera/Mic whenever Zoom or Teams launches

---

## Next (v0.3.0 — Swift CLI)
**Goal:** Replace fragile UI scripting with a small native tool.

- [ ] **Swift CLI (`icl`)**
  - Command: `icl select --app zoom|teams --camera ... --mic ...`
  - Faster, more reliable than AppleScript UI scripting
- [ ] **System doctor command**
  - `icl doctor` verifies Accessibility, Wi-Fi, Bluetooth, Handoff
  - Prints actionable fixes if checks fail
- [ ] **Binary distribution**
  - Universal macOS build attached to GitHub Releases
  - Draft Homebrew tap formula for testing
- [ ] **Profiles**
  - Config files in `profiles/`
  - Example: `icl select --profile default`

---

## Future (v0.4.0 — Menu Bar App)
**Goal:** Provide a simple, visible UX for camera/mic control.

- [ ] **Menubar status indicator**
  - Show “Using iPhone Camera ✅/❌”
  - Display current mic selection
- [ ] **Quick actions**
  - One-click switch to iPhone camera/mic
  - Show success/failure as a toast/notification
- [ ] **On-join automation**
  - Option to auto-select iPhone Camera/Mic when a meeting window opens

---

## Later (v0.5.0 — Ecosystem & Packaging)
**Goal:** Expand reach, simplify installs, and support more apps.

- [ ] **Packaging**
  - Publish official Homebrew formula
  - (Optional) Sign and notarize build to avoid Gatekeeper prompts
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

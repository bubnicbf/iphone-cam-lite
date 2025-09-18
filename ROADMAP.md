# iPhone Cam Lite — Roadmap

## Current (v0.2.0 — Hardening & Reliability)
- [ ] Retry/backoff when UI not ready
- [ ] Configurable device names (`config/devices.yml`)
- [ ] Structured logging + `make logs`
- [ ] Graceful error messages
- [ ] CI: lint & compile (shellcheck, osacompile, markdownlint)
- [ ] Troubleshooting guide
- [ ] (Optional) LaunchAgent auto-select on app launch

---

## Next (v0.3.0 — Swift CLI)
- [ ] Swift CLI (`icl`) for device selection
- [ ] `icl doctor` checks Accessibility, Handoff, Wi-Fi/Bluetooth
- [ ] Binary distribution (GitHub Releases, draft Homebrew tap)
- [ ] Configurable profiles (`profiles/default.yml`)

---

## Future (v0.4.0 — Menu Bar App)
- [ ] Menubar status indicator (camera/mic in use)
- [ ] One-click switch to iPhone camera/mic
- [ ] Auto-select on meeting join

---

## Later (v0.5.0 — Ecosystem & Packaging)
- [ ] Homebrew formula for easy install
- [ ] (Optional) Signed/notarized build
- [ ] Google Meet (browser) support
- [ ] Webex support

---

## Backlog / Stretch Ideas
- OBS scene presets + VirtualCam
- NDI/Syphon bridge
- Global hotkeys (via Hammerspoon)
- Remote control via HTTP server
- AI helpers (background blur, auto-framing)

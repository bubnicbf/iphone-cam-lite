# iphone-cam-lite

Lightweight helpers to use my iPhone as a webcam (Continuity Camera) on a Mac (tested on macOS Ventura+) for Zoom and Teams with no third-party drivers.

## What this does

- One-command launch for Zoom/Teams and auto-select **iPhone Camera** + **iPhone Microphone** via AppleScript UI scripting.
- Quick checks for Continuity Camera prerequisites.
- Optional `keepawake` to prevent macOS from sleeping during long calls.

## Requirements

- macOS Ventura or newer, iOS 16 or newer (Continuity Camera).
- Same Apple ID, Wi-Fi + Bluetooth ON, two-factor auth enabled, Handoff enabled.
- Place iPhone near your Mac (or mount it); unlock it the first time.
- Zoom or Microsoft Teams installed (from vendor or App Store).

## Quick start
```bash
make setup   # mark scripts executable & run prereq checks
make zoom    # launch Zoom, wait for UI, select iPhone Camera/Mic
make teams   # launch Teams, wait for UI, select iPhone Camera/Mic
```
If the selector scripts fail the first time (apps still loading), run the command again once the meeting window is visible.

## Scripts

- `scripts/check_prereqs.sh` – sanity checks for Continuity Camera.
- `scripts/start_zoom.sh` – launches Zoom and selects iPhone Camera/Mic.
- `scripts/start_teams.sh` – launches Teams and selects iPhone Camera/Mic.
- `scripts/select_zoom_camera.scpt` – AppleScript UI scripting for Zoom.
- `scripts/select_teams_camera.scpt` – AppleScript UI scripting for Teams.
- `scripts/keepawake.sh` – prevents sleep during calls (uses caffeinate).
- `scripts/reset_camera_services.sh` – quick reset of media agents if apps misbehave.

## Notes

- UI scripting depends on app menus and labels like “iPhone Camera” and “iPhone Microphone”. If you renamed your device, update the strings at the top of the AppleScript files.
- For Zoom, camera/mic menus can be accessed from the main window or meeting window; the script tries both.
- For Teams (new client), device settings are in Settings → Devices; the script opens that panel and selects the devices.

## Troubleshooting

- If your iPhone doesn’t appear:
	- Ensure Wi-Fi, Bluetooth, Handoff are on; same Apple ID on both devices.
	- Unlock iPhone; keep it near the Mac; mount it in landscape if possible.
	- Toggle camera services: `make reset-camera`
- If selection fails:
	- Open the app’s device menu once manually so macOS grants UI scripting access.
	- Re-run `make zoom` or `make teams` after the window is fully loaded.
	- Grant “Accessibility” permission to Terminal or your shell in System Settings → Privacy & Security → Accessibility.
# iphone-cam-lite

Lightweight helpers to use my iPhone as a webcam (Continuity Camera) on a Mac (tested on macOS Ventura+) for Zoom and Teams with no third-party drivers.

## What this does

- One-command launch for Zoom/Teams and auto-select **iPhone Camera** + **iPhone Microphone** via AppleScript UI scripting.
- Quick checks for Continuity Camera prerequisites.
- Optional `keepawake` to prevent macOS from sleeping during long calls.

## Quick start
```bash
make setup   # mark scripts executable & run prereq checks
make teams   # launch Teams, wait for UI, select iPhone Camera/Mic
```
If the selector scripts fail the first time (apps still loading), run the command again once the meeting window is visible.

## Notes

- UI scripting depends on app menus and labels like “iPhone Camera” and “iPhone Microphone”. If you renamed your device, update the strings at the top of the AppleScript files.
- For Zoom, camera/mic menus can be accessed from the main window or meeting window; the script tries both.
- For Teams (new client), device settings are in Settings → Devices; the script opens that panel and selects the devices.


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

## Configuring device names

By default the launchers select the camera named **iPhone Camera** and the
microphone named **iPhone Microphone** -- these must match the labels Zoom
or Teams actually shows in its own camera/microphone menus. If your device
is named differently (a renamed iPhone, a localized label, an external
camera, or an external microphone), set the `CAMERA_NAME` and/or
`MICROPHONE_NAME` environment variables at runtime -- no source file edits
needed. Either variable can be set independently; an unset or empty
variable falls back to its default.

```bash
CAMERA_NAME="Benjamin's iPhone Camera" make zoom
MICROPHONE_NAME="Studio USB Mic" make teams
CAMERA_NAME="Benjamin's iPhone Camera" MICROPHONE_NAME="Studio USB Mic" ./scripts/start_zoom.sh
```

Quote the value whenever the name contains spaces (as in the examples
above) so the shell treats it as a single argument.

## Configuring UI labels (localization)

`CAMERA_NAME`/`MICROPHONE_NAME` (above) control *which device* gets
selected. A separate set of variables controls the *menu and control
labels the automation looks for* in Zoom's and Teams' own interface --
use these only if your copy of Zoom or Teams is running in a language
other than English, or a UI change has moved/renamed the relevant menu or
button. Each one is optional; unset or empty falls back to the current
English label. The values must match what Zoom or Teams actually
displays (its visible label, or the accessibility title/description
behind it) -- not a translation you choose yourself.

Zoom (defaults shown):

| Variable | Default |
| --- | --- |
| `ZOOM_MEETING_MENU_LABEL` | `Meeting` |
| `ZOOM_CAMERA_MENU_LABEL` | `Select Camera` |
| `ZOOM_MICROPHONE_MENU_LABEL` | `Select Microphone` |
| `ZOOM_CAMERA_CONTROL_LABEL` | `Select a camera` |
| `ZOOM_MICROPHONE_CONTROL_LABEL` | `Select a microphone` |

Teams (defaults shown):

| Variable | Default |
| --- | --- |
| `TEAMS_SETTINGS_MENU_LABEL` | `Settings` |
| `TEAMS_DEVICES_LABEL` | `Devices` |
| `TEAMS_CAMERA_CONTROL_LABEL` | `Camera` |
| `TEAMS_MICROPHONE_CONTROL_LABEL` | `Microphone` |

Zoom example, a French build:
```bash
ZOOM_MEETING_MENU_LABEL="Réunion" \
ZOOM_CAMERA_MENU_LABEL="Sélectionner la caméra" \
ZOOM_MICROPHONE_MENU_LABEL="Sélectionner le microphone" \
  make zoom
```

Teams example, a German build:
```bash
TEAMS_SETTINGS_MENU_LABEL="Einstellungen" TEAMS_DEVICES_LABEL="Geräte" make teams
```

To find the exact label your installed app exposes, open **System
Settings → Privacy & Security → Accessibility → Accessibility Inspector**
(built into macOS; you do not need it for normal day-to-day use of this
repo) and inspect the menu item or button while Zoom/Teams is frontmost --
use its Title or Description field as the override value.

## Scripts

- `scripts/check_prereqs.sh` – sanity checks for Continuity Camera.
- `scripts/start_zoom.sh` – launches Zoom and selects iPhone Camera/Mic.
- `scripts/start_teams.sh` – launches Teams and selects iPhone Camera/Mic.
- `scripts/select_zoom_camera.scpt` – AppleScript UI scripting for Zoom.
- `scripts/select_teams_camera.scpt` – AppleScript UI scripting for Teams.
- `scripts/keepawake.sh` – prevents sleep during calls (uses caffeinate).
- `scripts/reset_camera_services.sh` – quick reset of media agents if apps misbehave.

## Notes

- Device names (“iPhone Camera”/“iPhone Microphone”) and UI labels (menu/button text like “Meeting” or “Devices”) are both configurable at runtime via environment variables -- see “Configuring device names” and “Configuring UI labels” above -- so a renamed device, a non-English Zoom/Teams install, or a build that relocated a menu does not require editing the AppleScript files.
- Accessibility permission for your terminal/shell is still required either way (see Troubleshooting) -- UI-label overrides change what the automation looks for, not whether it's allowed to control the app.
- For Zoom, the launcher first tries the Meeting menu route, then falls back to a bounded accessibility search across Zoom's currently visible windows if that route doesn't resolve both devices.
- For Teams (new client), the launcher opens Settings → Devices (falling back to the Command-, shortcut if the Settings menu item isn't found) and then searches visible settings windows/sheets for the camera and microphone controls.
- Both selectors require that *both* the camera and the microphone were actually confirmed selected before reporting success, and exit with a specific, actionable error (naming the device or stage that failed) rather than continuing silently -- there is no promise of compatibility with every future Zoom or Teams release, since this remains UI/accessibility scripting rather than an official automation API; a large enough interface change can still require an updated label or a newer version of this repo.

## Troubleshooting

- If your iPhone doesn’t appear:
	- Ensure Wi-Fi, Bluetooth, Handoff are on; same Apple ID on both devices.
	- Unlock iPhone; keep it near the Mac; mount it in landscape if possible.
	- Toggle camera services: `make reset-camera`
- If selection fails:
	- Open the app’s device menu once manually so macOS grants UI scripting access.
	- Re-run `make zoom` or `make teams` after the window is fully loaded.
	- Grant “Accessibility” permission to Terminal or your shell in System Settings → Privacy & Security → Accessibility.
- If the launcher exits with a selector error naming a specific device or stage (for example, `camera "..." was not selected`, `Teams Devices panel could not be located`, or an ambiguous-match error):
	- The error text names exactly which device or step failed -- start there rather than re-running blindly.
	- Confirm the requested device name (`CAMERA_NAME`/`MICROPHONE_NAME`) exactly matches an entry in the app's own camera/microphone menu.
	- If Zoom or Teams is not running in English, or a UI update changed a menu/button, set the matching `ZOOM_*`/`TEAMS_*` label override (see “Configuring UI labels” above).
	- An “ambiguous match” error means more than one control matched a label -- make the corresponding label override more specific.
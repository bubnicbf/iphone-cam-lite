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
- Teams must already be signed in before you run `make teams`: the automation only drives the Settings → Devices UI of an already-authenticated client -- it never enters credentials, clicks a sign-in or "Pick an account" button, or completes any part of authentication for you. If Teams is signed out, mid-sign-in, or still loading its main window when the launcher runs, device selection is not expected to succeed; sign in and let Teams fully load first, then run `make teams` again.
- Both selectors require that *both* the camera and the microphone are read back and confirmed selected via the app's own accessibility state (a menu item's mark/checked state, or a pop-up control's resulting value) -- never inferred merely from a click command completing -- before reporting success, and exit nonzero with a specific, actionable error (naming the device or stage that failed, and which of item-not-found / click-failed / value-unchanged / wrong-device / unreadable-state / timeout / ambiguous-match caused it) rather than continuing silently -- there is no promise of compatibility with every future Zoom or Teams release, since this remains UI/accessibility scripting rather than an official automation API; a large enough interface change can still require an updated label, or can stop exposing the accessibility state this confirmation relies on, or a newer version of this repo.

## Troubleshooting

- If `make teams` fails right after launch, or fails with a Settings/Devices error that doesn't match anything in your setup:
	- Open Microsoft Teams yourself first, sign in if prompted, and wait until the main Teams window (chats/calls/teams list) is fully loaded before running `make teams` -- the automation does not detect or wait out a sign-in, account-selection, or loading screen, and does not interact with authentication UI in any way.
- If your iPhone doesn’t appear:
	- Ensure Wi-Fi, Bluetooth, Handoff are on; same Apple ID on both devices.
	- Unlock iPhone; keep it near the Mac; mount it in landscape if possible.
	- Toggle camera services: `make reset-camera`
- If selection fails:
	- Open the app’s device menu once manually so macOS grants UI scripting access.
	- Re-run `make zoom` or `make teams` after the window is fully loaded.
	- Grant “Accessibility” permission to Terminal or your shell in System Settings → Privacy & Security → Accessibility.
- If the launcher exits with a selector error naming a specific device or stage (for example, `camera "..." was not confirmed selected`, `Teams settings could not be opened`, `Teams Devices panel could not be located`, or an ambiguous-match error):
	- This is expected behavior, not a bug: `make zoom`/`make teams` now exits nonzero and reports the exact stage that failed (opening a menu, opening Settings, locating Devices, locating the camera/microphone control, or confirming the requested device item was actually selected) whenever UI automation cannot confirm *both* devices were actually selected -- it never reports success on a partial result, an unconfirmed click, or a guess.
	- The error text names exactly which device or step failed, and includes the underlying AppleScript error message and error number where one was available -- start there rather than re-running blindly.
	- Confirm the requested device name (`CAMERA_NAME`/`MICROPHONE_NAME`) exactly matches an entry in the app's own camera/microphone menu, including case, punctuation, and spacing -- matching is exact (after trimming leading/trailing whitespace only), never a substring match, so `"iPhone"` will not match an item literally named `"iPhone Camera"`.
	- If Zoom or Teams is not running in English, or a UI update changed a menu/button, set the matching `ZOOM_*`/`TEAMS_*` label override (see “Configuring UI labels” above).
	- Confirm Accessibility permission is still granted to Terminal/your shell (permission can be silently revoked by a macOS update or app reinstall).
	- If none of the above explains it, a recent Zoom or Teams update may have changed its interface in a way label overrides alone can't bridge -- check the installed application version and whether this repository has a newer release for it.
	- An “ambiguous match” error means more than one control matched a label -- make the corresponding label override more specific.
- If the error says a requested item was not found (a "not found" or "item not found" style message, meaning a menu item or pop-up entry for the requested device could not be located at all -- distinct from a click that failed on an item that *was* found):
	- The device name almost certainly doesn't match what the app currently lists -- open the app's own camera/microphone menu and copy the name exactly, or set a `CAMERA_NAME`/`MICROPHONE_NAME` override that does.
- If the error says a click failed (a "click failed" style message, naming the underlying AppleScript error and number):
	- The requested item was located, but the click itself did not go through -- this can mean the window lost focus, the control was covered or disabled, or a transient accessibility glitch occurred. Re-run after bringing the app's window to the front; the underlying error message/number can help narrow down the cause.
- If the error says the selection remained unchanged after clicking:
	- The click was issued, but the app's own accessibility state still reports the same value it had before the click, within the short confirmation window -- this can mean the click landed but the app ignored it, the requested device is unavailable/disconnected in the app itself, or the app is slower than usual to update its UI. Try again once the app's window is idle and frontmost, and confirm the device still appears in the app's own menu.
- If the error says a different device became selected:
	- The click changed the app's selection, but to something other than the exact requested device name -- this can mean a similarly named device took the click, the requested device disappeared mid-selection, or the app's own list reordered. Confirm the requested device name is still exactly correct (see the exact-match note above) and still present in the app's own menu.
- If the error says a selection state was unreadable or could not be confirmed:
	- The app isn't exposing the accessibility attribute this confirmation relies on (for example a menu item's mark character, or a control's value/title) for that control right now -- this can happen after an app update changes what it exposes, or if the relevant window/menu isn't in the expected state. Re-run after bringing the app's window to the front, and check whether a newer version of this repository has an updated confirmation strategy for the installed app version.
- If the error mentions a confirmation timeout:
	- The bounded wait (a few seconds, briefly polling) elapsed before the app's accessibility state confirmed the change -- this is deliberate and never indefinite. A consistently slow app, an unusually large device list, or a partially unresponsive UI can all cause this; re-running after the app has fully finished loading its window usually resolves it.
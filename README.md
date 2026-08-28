# iphone-cam-lite

A native macOS menu bar app that uses your iPhone as a webcam (Continuity
Camera) for Zoom and Microsoft Teams, with no third-party drivers — select
**iPhone Camera** and **iPhone Microphone** in either app from one menu
bar click, with the selection confirmed, not assumed.

## What this does

- A `MenuBarExtra` app (`iPhoneCamLite`) with one-click "select iPhone
  Camera/Microphone" actions for Zoom and Teams, live status, and a
  keep-awake toggle for long calls.
- An Onboarding window that explains and checks the Accessibility and
  Apple Events permissions the app needs — and never claims a permission
  is granted when it isn't.
- A read-only Diagnostics window for Continuity Camera prerequisites
  (Wi-Fi, Bluetooth, macOS version, installed apps, permissions), plus a
  manual camera-service-reset action.
- Typed, persisted Settings for the camera/microphone device names and
  the menu/control labels the automation looks for (for non-English
  installs or a relocated menu).

This project used to be a collection of shell scripts and AppleScript
files invoked via `make zoom`/`make teams`. That architecture has been
replaced by the native Swift app described here; see
[docs/MIGRATION.md](docs/MIGRATION.md) for exactly what moved where and
why, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the app is
put together.

## Requirements

- macOS Ventura (13) or newer, iOS 16 or newer (Continuity Camera).
- Same Apple ID, Wi-Fi + Bluetooth ON, two-factor auth enabled, Handoff
  enabled.
- Place iPhone near your Mac (or mount it); unlock it the first time.
- Zoom or Microsoft Teams installed (from vendor or App Store).
- To build from source: Xcode 15+ / a Swift 5.9+ toolchain.

## Quick start

Build and run from source (see [CONTRIBUTING.md](CONTRIBUTING.md) for a
full development setup):

```sh
git clone git@github.com:bubnicbf/iphone-cam-lite.git
cd iphone-cam-lite
git checkout dev
make build   # swift build
make app     # package a runnable .app bundle into dist/ (see docs/ARCHITECTURE.md)
```

Open the app once: it shows an onboarding flow that walks through
granting Accessibility and Apple Events permissions (System Settings →
Privacy & Security), which the automation needs to select devices inside
Zoom/Teams. Nothing is granted automatically or silently assumed.

Then from the menu bar icon: choose **Select iPhone Camera & Mic in
Zoom** or **... in Teams**. The app launches the target application if
needed, waits for it to be ready, drives its device-selection UI, and
reports success only once both the camera and microphone are read back
and confirmed selected.

## Configuring device names and UI labels

Open the app's **Settings** window (from the menu bar menu) to set:

- **Camera name** / **Microphone name** — which device to select; these
  must match the labels Zoom or Teams actually shows in its own
  camera/microphone menus. Leave either blank to use the default
  (**iPhone Camera** / **iPhone Microphone**) — an empty value always
  falls back to the default independently of the other field.
- **Menu/control label overrides** (Zoom: meeting menu, camera/microphone
  submenu and control labels; Teams: settings menu, devices label, camera
  and microphone control labels) — use these only if your copy of Zoom or
  Teams runs in a language other than English, or an app update
  relocated/renamed the relevant menu or button. Each is optional; a
  blank value falls back to the current English label. The value must
  match what Zoom or Teams actually displays (its visible label, or the
  accessibility title/description behind it) — not a translation you
  choose yourself.

To find the exact label your installed app exposes, open **System
Settings → Privacy & Security → Accessibility → Accessibility Inspector**
(built into macOS) and inspect the menu item or button while Zoom/Teams
is frontmost — use its Title or Description field as the override value.

Settings are persisted by the app; unlike the old scripts, there is no
per-invocation environment-variable override — see
[docs/MIGRATION.md](docs/MIGRATION.md#configuration-model-change) for why.

## How device selection is verified

Both the camera and the microphone are read back and confirmed selected
via the target app's own accessibility state (a menu item's mark/checked
state, or a pop-up control's resulting value) — never inferred merely
from a click completing — before the app reports success. A failure
reports the specific stage and device that failed (item not found, click
failed, value unchanged, wrong device selected, selection state
unreadable, confirmation timed out, or an ambiguous match) rather than
failing silently or reporting a partial success as a full one. There is
no promise of compatibility with every future Zoom or Teams release,
since selection still relies on UI/accessibility automation rather than
an official device-selection API — see "Known limitations" in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Teams sign-in

Teams must already be signed in before you select devices: the
automation only drives the Settings → Devices UI of an already
authenticated client — it never enters credentials, clicks a sign-in or
account-picker button, or completes any part of authentication for you.
If Teams is signed out, mid-sign-in, or still loading its main window,
device selection is not expected to succeed; sign in and let Teams fully
load first, then try again.

## Troubleshooting

- **Permissions**: Onboarding and Diagnostics both check Accessibility
  and Apple Events trust with a read-only check (no prompt forced from
  outside System Settings) and link you to the right System Settings
  pane if either is missing. If a selection fails with a permission-like
  error, check there first — permission can be silently revoked by a
  macOS update or app reinstall.
- **iPhone not appearing**: confirm Wi-Fi, Bluetooth, and Handoff are on
  and the same Apple ID is signed in on both devices; unlock the iPhone
  and keep it near the Mac. Diagnostics can flag Wi-Fi/Bluetooth as off;
  the menu bar app's camera-service-reset action restarts the relevant
  media services if the camera stops responding after that.
- **Selection fails**: open the app's own device menu once manually so
  macOS grants UI scripting access, then retry. Confirm the configured
  device name exactly matches an entry in the app's own camera/microphone
  menu, including case, punctuation, and spacing — matching is exact
  after trimming leading/trailing whitespace only, never a substring or
  case-insensitive match. If Zoom or Teams isn't running in English, or
  an update moved a menu/button, set the matching label override in
  Settings.
- **Specific selection errors**: the app surfaces a specific, actionable
  error naming the device or stage that failed rather than a generic
  failure — see "How device selection is verified" above and
  `docs/ARCHITECTURE.md`'s error taxonomy for what each one means.

## Testing

```sh
make test
```

Runs the SwiftPM test suite (`CameraCoreTests`, `AdapterFixtureTests`,
`UITests`) — fully hermetic; it never launches Zoom or Teams, never
changes your actual camera/microphone selection, and never restarts real
system services. See [docs/TESTING.md](docs/TESTING.md) for what each
target covers and how to run a single suite.

```sh
make lint
```

Builds the package graph and validates the privacy manifest (see
`docs/TESTING.md`).

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up a development
environment, the branching model, and what's expected of a pull request.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the module layout
and design rationale.

## Releases

```sh
make dist VERSION=1.2.3
```

Builds and packages the `.app` into `dist/` (git-ignored) via
`scripts/package_app.sh`. Run `make clean-dist` to remove `dist/`.

See [CHANGELOG.md](CHANGELOG.md) for release history, and
[SECURITY.md](SECURITY.md) for how to report a vulnerability.

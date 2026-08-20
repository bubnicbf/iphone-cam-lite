#!/usr/bin/env bash
set -euo pipefail

# Resolve this script's own directory from BASH_SOURCE (not the caller's
# current working directory), so sibling resources (the AppleScript
# selector) can always be found regardless of where or how this script is
# invoked -- from the repo root, from another directory, by absolute path,
# or by automation with an unrelated working directory. This is a portable
# (dirname + cd + pwd) pattern that works on the macOS-provided Bash
# without relying on GNU-only readlink -f/realpath.
if ! SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; then
  echo "✖ Could not resolve the directory containing this script." >&2
  exit 1
fi
SELECTOR_PATH="$SCRIPT_DIR/select_zoom_camera.scpt"

# Verify the selector resource is present before doing anything else (in
# particular, before launching the application), so a missing/misplaced
# resource produces a clear, immediate error instead of launching Zoom
# only to fail confusingly at the AppleScript step.
if [[ ! -f "$SELECTOR_PATH" || ! -r "$SELECTOR_PATH" ]]; then
  echo "✖ Expected AppleScript selector not found or not readable: $SELECTOR_PATH" >&2
  exit 1
fi

APP_NAME="Zoom"
APP_MATCH="zoom.us"

# Exact executable process name(s) that count as "Zoom is actually
# running". Matched with `pgrep -x` (exact executable-name match) only --
# never `pgrep -f` (full command-line substring match), which can match
# any unrelated process whose arguments merely happen to contain the app
# name (a shell command, a log line, a test process, an editor buffer,
# etc.) and would falsely report Zoom as started.
#
# "zoom.us" is Zoom's documented main GUI process/executable name on
# macOS (it is also the identifier Zoom's own installer registers with
# Launch Services, which is why `open -ga "zoom.us"` above already works),
# distinct from helper processes such as "CptHost" or "ZoomOpener". This
# environment has no real macOS install to read the app bundle's
# CFBundleExecutable value directly, so this name is taken from Zoom's
# published process-name documentation rather than live-verified bundle
# metadata; update it here if a future Zoom build ships under a different
# executable name.
ZOOM_PROCESS_NAMES=("zoom.us")

# Configurable so automated tests can use a small attempt limit and
# zero-length delays. Defaults preserve the existing production timing.
LAUNCHER_ATTEMPTS="${LAUNCHER_ATTEMPTS:-20}"
LAUNCHER_POLL_INTERVAL="${LAUNCHER_POLL_INTERVAL:-0.5}"
LAUNCHER_SETTLE_DELAY="${LAUNCHER_SETTLE_DELAY:-2}"
OSASCRIPT_BIN="${OSASCRIPT_BIN:-/usr/bin/osascript}"

# Desired camera/microphone menu labels, configurable at runtime via the
# CAMERA_NAME / MICROPHONE_NAME environment variables (":-" applies the
# default for both "unset" and "set but empty", per the documented
# defaults in README.md) so users are never required to edit the
# AppleScript source files to select a differently named device.
CAMERA_NAME="${CAMERA_NAME:-iPhone Camera}"
MICROPHONE_NAME="${MICROPHONE_NAME:-iPhone Microphone}"

if ! [[ "$LAUNCHER_ATTEMPTS" =~ ^[0-9]+$ ]] || [[ "$LAUNCHER_ATTEMPTS" -lt 1 ]]; then
  echo "✖ Invalid LAUNCHER_ATTEMPTS value: '$LAUNCHER_ATTEMPTS' (must be a positive integer)." >&2
  exit 1
fi

if ! open -ga "$APP_MATCH"; then
  echo "✖ Failed to launch $APP_NAME (the 'open' command reported an error). Is $APP_NAME installed?" >&2
  exit 1
fi

# process_running checks every exact candidate executable name in turn and
# reports success if any of them is currently running. Checking multiple
# candidates here always counts as a single polling attempt in the caller's
# loop below -- it never consumes more than one iteration of $attempts no
# matter how many names are in the candidate list.
process_running() {
  local name
  for name in "$@"; do
    if pgrep -x "$name" >/dev/null; then
      return 0
    fi
  done
  return 1
}

# Wait for Zoom to spin up (meeting or main window). "found" tracks whether
# the process actually appeared, so a loop that ends because the attempt
# limit was reached is never confused with a successful launch.
found=false
attempts=0
while [[ "$attempts" -lt "$LAUNCHER_ATTEMPTS" ]]; do
  if process_running "${ZOOM_PROCESS_NAMES[@]}"; then
    found=true
    break
  fi
  sleep "$LAUNCHER_POLL_INTERVAL"
  attempts=$((attempts+1))
done

if [[ "$found" != true ]]; then
  echo "✖ $APP_NAME did not start within the allowed startup period ($LAUNCHER_ATTEMPTS attempts). Its process never appeared." >&2
  exit 1
fi

# Give the UI a moment
sleep "$LAUNCHER_SETTLE_DELAY"

# Select devices via AppleScript
# Pass the resolved names through as distinct argv entries (never by
# building a command string or using eval), so osascript's "on run argv"
# handler receives each one as exactly one argument, whitespace,
# apostrophes, parentheses, and Unicode characters intact.
"$OSASCRIPT_BIN" "$SELECTOR_PATH" "$CAMERA_NAME" "$MICROPHONE_NAME"

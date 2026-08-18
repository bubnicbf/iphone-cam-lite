#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Zoom"
APP_MATCH="zoom.us"

# Configurable so automated tests can use a small attempt limit and
# zero-length delays. Defaults preserve the existing production timing.
LAUNCHER_ATTEMPTS="${LAUNCHER_ATTEMPTS:-20}"
LAUNCHER_POLL_INTERVAL="${LAUNCHER_POLL_INTERVAL:-0.5}"
LAUNCHER_SETTLE_DELAY="${LAUNCHER_SETTLE_DELAY:-2}"
OSASCRIPT_BIN="${OSASCRIPT_BIN:-/usr/bin/osascript}"

if ! [[ "$LAUNCHER_ATTEMPTS" =~ ^[0-9]+$ ]] || [[ "$LAUNCHER_ATTEMPTS" -lt 1 ]]; then
  echo "✖ Invalid LAUNCHER_ATTEMPTS value: '$LAUNCHER_ATTEMPTS' (must be a positive integer)." >&2
  exit 1
fi

if ! open -ga "$APP_MATCH"; then
  echo "✖ Failed to launch $APP_NAME (the 'open' command reported an error). Is $APP_NAME installed?" >&2
  exit 1
fi

# Wait for Zoom to spin up (meeting or main window). "found" tracks whether
# the process actually appeared, so a loop that ends because the attempt
# limit was reached is never confused with a successful launch.
found=false
attempts=0
while [[ "$attempts" -lt "$LAUNCHER_ATTEMPTS" ]]; do
  if pgrep -f "$APP_MATCH" >/dev/null; then
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
"$OSASCRIPT_BIN" scripts/select_zoom_camera.scpt

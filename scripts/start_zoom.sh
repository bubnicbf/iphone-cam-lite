#!/usr/bin/env bash
set -euo pipefail

open -ga "zoom.us" || true

# Wait for Zoom to spin up (meeting or main window)
attempts=0
while ! pgrep -f "zoom.us" >/dev/null && [[ $attempts -lt 20 ]]; do
  sleep 0.5
  attempts=$((attempts+1))
done
# Give the UI a moment
sleep 2

# Select devices via AppleScript
/usr/bin/osascript scripts/select_zoom_camera.scpt

#!/usr/bin/env bash
set -euo pipefail

# App name varies; adjust if using classic Teams
APP_NAME="Microsoft Teams"

open -ga "$APP_NAME" || true

attempts=0
while ! pgrep -f "$APP_NAME" >/dev/null && [[ $attempts -lt 30 ]]; do
  sleep 0.5
  attempts=$((attempts+1))
done
sleep 3

/usr/bin/osascript scripts/select_teams_camera.scpt

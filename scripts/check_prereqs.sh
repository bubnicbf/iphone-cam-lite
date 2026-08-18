#!/usr/bin/env bash
set -euo pipefail

ok=true

echo "▶ Checking Continuity Camera prerequisites…"

# macOS version check
MACOS_VER="$(sw_vers -productVersion)"
MAJOR="${MACOS_VER%%.*}"
if [[ "$MAJOR" -lt 13 ]]; then
  echo "✖ macOS $MACOS_VER < 13 (Ventura). Continuity Camera needs Ventura+."
  ok=false
else
  echo "✓ macOS $MACOS_VER"
fi

# Bluetooth + WiFi status (best-effort)
BT_ON=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null || echo 1)
if [[ "$BT_ON" != "1" ]]; then
  echo "✖ Bluetooth appears off. Turn it on."
  ok=false
else
  echo "✓ Bluetooth on"
fi

WIFI_DEV=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/AirPort/ {print $2}')
if ifconfig en0 2>/dev/null | grep -q 'status: active' || ifconfig en1 2>/dev/null | grep -q 'status: active'; then
  echo "✓ Wi-Fi connected"
else
  echo "✖ Wi-Fi not active. Connect to Wi-Fi."
  ok=false
fi

# Accessibility permission hint (cannot auto-check reliably)
echo "ℹ Ensure your terminal has Accessibility permissions: System Settings → Privacy & Security → Accessibility."

$ok || { echo "Prereq checks found issues."; exit 1; }
echo "✓ All checks passed."

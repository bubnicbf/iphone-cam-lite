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

# Bluetooth status (best-effort). A failed or unrecognized preference read
# must never be treated as proof Bluetooth is enabled, so the read's
# success/failure and its value are evaluated separately rather than
# substituting a default value on failure.
BT_STATE="unknown"
if BT_ON="$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null)"; then
  case "$BT_ON" in
    1) BT_STATE="on" ;;
    0) BT_STATE="off" ;;
    *) BT_STATE="unknown" ;;
  esac
fi

case "$BT_STATE" in
  on)
    echo "✓ Bluetooth on"
    ;;
  off)
    echo "✖ Bluetooth appears off. Turn it on."
    ok=false
    ;;
  *)
    echo "✖ Could not determine Bluetooth state (preference read failed or returned an unexpected value)."
    ok=false
    ;;
esac

# WiFi status (best-effort)
if ifconfig en0 2>/dev/null | grep -q 'status: active' || ifconfig en1 2>/dev/null | grep -q 'status: active'; then
  echo "✓ Wi-Fi connected"
else
  echo "✖ Could not identify the Wi-Fi hardware interface (networksetup unavailable or no Wi-Fi/AirPort port found)."
  ok=false
fi

# Accessibility permission hint (cannot auto-check reliably)
echo "ℹ Ensure your terminal has Accessibility permissions: System Settings → Privacy & Security → Accessibility."

$ok || { echo "Prereq checks found issues."; exit 1; }
echo "✓ All checks passed."

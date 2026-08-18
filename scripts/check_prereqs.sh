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

# Resolve the networksetup binary. Tests override this to point at a mock
# so Wi-Fi device discovery never depends on real hardware.
NETWORKSETUP_BIN="${NETWORKSETUP_BIN:-/usr/sbin/networksetup}"

# find_wifi_device prints the BSD device name (e.g. en0, en7) associated
# with the Mac's Wi-Fi hardware port, using the public
# `networksetup -listallhardwareports` listing. Both the modern "Wi-Fi"
# label and the older "AirPort" label are recognized.
#
# Returns nonzero if networksetup fails, produces no output, or no
# Wi-Fi/AirPort hardware port is found. This is an expected, recoverable
# condition -- callers must check it explicitly rather than relying on
# set -e, since a Mac's hardware ports are not guaranteed to include one.
find_wifi_device() {
  local ports_output
  if ! ports_output="$("$NETWORKSETUP_BIN" -listallhardwareports 2>/dev/null)"; then
    return 1
  fi
  if [[ -z "$ports_output" ]]; then
    return 1
  fi

  local device
  if ! device="$(printf '%s\n' "$ports_output" | awk '
    /^Hardware Port: (Wi-Fi|AirPort)[[:space:]]*$/ { want = 1; next }
    /^Hardware Port:/                              { want = 0 }
    want && /^Device: /                             { sub(/^Device: /, ""); print; exit }
  ')"; then
    return 1
  fi
  if [[ -z "$device" ]]; then
    return 1
  fi

  printf '%s\n' "$device"
}

wifi_device=""
if wifi_device="$(find_wifi_device)"; then
  if ifconfig "$wifi_device" 2>/dev/null | grep -q 'status: active'; then
    echo "✓ Wi-Fi connected ($wifi_device)"
  else
    echo "✖ Wi-Fi not active on $wifi_device. Connect to Wi-Fi."
    ok=false
  fi
else
  echo "✖ Could not identify the Wi-Fi hardware interface (networksetup unavailable or no Wi-Fi/AirPort port found)."
  ok=false
fi

# Accessibility permission hint (cannot auto-check reliably)
echo "ℹ Ensure your terminal has Accessibility permissions: System Settings → Privacy & Security → Accessibility."

$ok || { echo "Prereq checks found issues."; exit 1; }
echo "✓ All checks passed."

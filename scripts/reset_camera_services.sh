#!/usr/bin/env bash
set -euo pipefail
echo "Restarting camera/media agents…"
launchctl kickstart -k system/com.apple.cmio.AVCAssistant 2>/dev/null || true
launchctl kickstart -k gui/$UID/com.apple.cmio.AppleCameraAssistant 2>/dev/null || true
pkill -f "VCam" 2>/dev/null || true
echo "Done. If apps were open, relaunch them."

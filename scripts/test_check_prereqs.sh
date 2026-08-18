#!/usr/bin/env bash
# Regression test for scripts/check_prereqs.sh.
#
# Covers two historical bugs:
#
# 1. "Silent premature exit": check_prereqs.sh used to call the obsolete
#    private airport utility inside a command substitution while
#    set -euo pipefail was active. When that command was missing or
#    failed, the script exited immediately after the Bluetooth check and
#    never reported Wi-Fi status, the Accessibility reminder, or a final
#    result.
#
# 2. "Bluetooth false positive": check_prereqs.sh used to fall back to the
#    literal value "1" whenever the Bluetooth `defaults read` failed
#    (`... || echo 1`), so a failed preference read was reported as
#    "Bluetooth on". The fix evaluates the read's success/failure and its
#    value separately, so failure, empty output, and unrecognized values
#    are all treated as an unknown Bluetooth state rather than "enabled".
#
# This test mocks sw_vers, defaults, and ifconfig with safe test doubles on
# PATH (never touching real system state) and exercises the script's
# success, Wi-Fi-failure, and Bluetooth enabled/disabled/unknown-state
# scenarios. It never launches Zoom, Teams, AppleScript UI automation,
# caffeinate, or camera-reset commands.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prereq_script="$repo_root/scripts/check_prereqs.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [[ ! -f "$prereq_script" ]]; then
  fail "scripts/check_prereqs.sh not found at $prereq_script"
fi

# --- Static regression assertions -------------------------------------
# These guard against the obsolete airport dependency and the Bluetooth
# false-positive fallback reappearing, even if the runtime scenarios below
# were somehow skipped.
if grep -q 'Apple80211.framework' "$prereq_script"; then
  fail "scripts/check_prereqs.sh still references the private Apple80211 airport path"
fi
if grep -Eq 'airport[[:space:]]+-I' "$prereq_script"; then
  fail "scripts/check_prereqs.sh still invokes 'airport -I'"
fi
if grep -q 'WIFI_DEV' "$prereq_script"; then
  fail "scripts/check_prereqs.sh still contains the unused WIFI_DEV assignment"
fi
echo "PASS: no obsolete airport path, 'airport -I' invocation, or WIFI_DEV assignment found"

if grep -Eq 'ControllerPowerState.*\|\|[[:space:]]*echo 1' "$prereq_script"; then
  fail "scripts/check_prereqs.sh still falls back to 'echo 1' when the Bluetooth defaults read fails"
fi
echo "PASS: no 'defaults read ... || echo 1' Bluetooth fallback found"

# --- Mock command sandbox ----------------------------------------------
mock_dir="$(mktemp -d)"
trap 'rm -rf "$mock_dir"' EXIT

write_mock() {
  local name="$1" body="$2"
  cat > "$mock_dir/$name" << MOCKEOF
#!/usr/bin/env bash
$body
MOCKEOF
  chmod +x "$mock_dir/$name"
}

# write_networksetup_mock <filename> <hardware-ports-listing-text>
# Creates a mock at $mock_dir/<filename> that prints the given text when
# invoked as "<filename> -listallhardwareports", mimicking the real
# `networksetup -listallhardwareports` output format.
write_networksetup_mock() {
  local name="$1" ports_text="$2"
  local data_file="$mock_dir/${name}.ports"
  printf '%s\n' "$ports_text" > "$data_file"
  cat > "$mock_dir/$name" << MOCKEOF
#!/usr/bin/env bash
if [[ "\$1" == "-listallhardwareports" ]]; then
  cat "$data_file"
  exit 0
fi
exit 1
MOCKEOF
  chmod +x "$mock_dir/$name"
}

# write_failing_networksetup_mock <filename>
# Creates a mock that always fails, simulating networksetup being broken
# or unavailable.
write_failing_networksetup_mock() {
  local name="$1"
  cat > "$mock_dir/$name" << 'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
  chmod +x "$mock_dir/$name"
}

# write_ifconfig_mock <active-device> [<active-device> ...]
# Creates the "ifconfig" mock (must be named exactly "ifconfig" since it is
# resolved via PATH). Reports "status: active" only for the listed
# device(s), and logs every device it was queried with to $IFCONFIG_LOG (if
# set) so tests can verify which interface the implementation inspected.
write_ifconfig_mock() {
  local data_file="$mock_dir/ifconfig.active"
  printf '%s\n' "$@" > "$data_file"
  cat > "$mock_dir/ifconfig" << MOCKEOF
#!/usr/bin/env bash
if [[ -n "\${IFCONFIG_LOG:-}" ]]; then
  echo "\$1" >> "\$IFCONFIG_LOG"
fi
if grep -qxF "\$1" "$data_file" 2>/dev/null; then
  echo "status: active"
fi
MOCKEOF
  chmod +x "$mock_dir/ifconfig"
}

run_prereqs() {
  # Runs check_prereqs.sh with the mock directory first in PATH. Uses
  # 'bash <script>' rather than direct execution so this test does not
  # depend on the script's filesystem executable bit. NETWORKSETUP_BIN is
  # expected to already be exported by the caller.
  PATH="$mock_dir:$PATH" bash "$prereq_script"
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "expected output to contain $label ('$needle') but it did not"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "expected output to NOT contain $label ('$needle') but it did"
  fi
}

write_mock sw_vers '
if [[ "${1:-}" == "-productVersion" ]]; then
  echo "14.5"
fi
'
write_mock ifconfig '
if [[ "${1:-}" == "en0" ]]; then
  echo "status: active"
fi
'

# --- Scenario 1: macOS Ventura+, Bluetooth on, Wi-Fi active, no airport ---
echo
echo "== Scenario: macOS Ventura+, Bluetooth on, Wi-Fi active =="

write_mock defaults '
echo 1
'
# Deliberately no "airport" mock is provided: the fixed script must not
# call it at all. If it did, the mock PATH would fall through to the real
# (absent/obsolete) system binary and reproduce the original bug.

set +e
output="$(run_prereqs 2>&1)"
status=$?
set -e

echo "$output"

if [[ $status -ne 0 ]]; then
  fail "expected check_prereqs.sh to exit 0 when the dynamically discovered Wi-Fi device (en7) is active, got $status"
fi

assert_contains "$output" "✓ Bluetooth on" "the Bluetooth success result"
assert_not_contains "$output" "Could not determine Bluetooth state" "the Bluetooth-state-unknown message (success scenario)"
assert_not_contains "$output" "Bluetooth appears off" "the Bluetooth-off message (success scenario)"
assert_contains "$output" "Wi-Fi connected" "the Wi-Fi connected result"
assert_contains "$output" "Accessibility permissions" "the Accessibility permission reminder"
assert_contains "$output" "All checks passed" "the final all-checks-passed result"

ifconfig_calls="$(cat "$IFCONFIG_LOG" 2>/dev/null || true)"
assert_contains "$ifconfig_calls" "en7" "an ifconfig call for the dynamically discovered device en7"
if [[ "$ifconfig_calls" == *"en0"* || "$ifconfig_calls" == *"en1"* ]]; then
  fail "check_prereqs.sh queried en0/en1 via ifconfig even though Wi-Fi is on en7 -- unexplained hard-coded fallback detected: [$ifconfig_calls]"
fi

echo "PASS: dynamic discovery found en7, queried only en7 via ifconfig, and the success scenario passed"

# --- Scenario: an active but unrelated en0 must not be a false positive --
echo
echo "== Scenario: an active but unrelated en0 must not produce a false positive =="

: > "$IFCONFIG_LOG"
write_ifconfig_mock en0
write_networksetup_mock networksetup_falsepos "$(cat << 'PORTS'
Hardware Port: Ethernet
Device: en0
Ethernet Address: aa:aa:aa:aa:aa:aa

Hardware Port: Wi-Fi
Device: en5
Ethernet Address: dd:dd:dd:dd:dd:dd
PORTS
)"
export NETWORKSETUP_BIN="$mock_dir/networksetup_falsepos"

set +e
fp_output="$(run_prereqs 2>&1)"
fp_status=$?
set -e

echo "$fp_output"

if [[ $fp_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when the real Wi-Fi device (en5) is inactive, even though unrelated en0 is active, got 0"
fi

assert_contains "$fp_output" "Wi-Fi not active" "the Wi-Fi failure message (false-positive-prevention scenario)"
assert_contains "$fp_output" "en5" "the actual Wi-Fi device name (en5) in the failure message"
assert_contains "$fp_output" "Accessibility permissions" "the Accessibility permission reminder (false-positive-prevention scenario)"
assert_contains "$fp_output" "Prereq checks found issues" "the prerequisite-failure summary (false-positive-prevention scenario)"

fp_calls="$(cat "$IFCONFIG_LOG" 2>/dev/null || true)"
assert_contains "$fp_calls" "en5" "an ifconfig call for the real Wi-Fi device en5"

echo "PASS: an active but unrelated en0 interface did not produce a false Wi-Fi-connected result"

# --- Scenario: Wi-Fi device cannot be discovered (networksetup failure) --
echo
echo "== Scenario: Wi-Fi device cannot be discovered (networksetup failure) =="

write_failing_networksetup_mock networksetup_broken
export NETWORKSETUP_BIN="$mock_dir/networksetup_broken"
: > "$IFCONFIG_LOG"
write_ifconfig_mock en0

set +e
df_output="$(run_prereqs 2>&1)"
df_status=$?
set -e

echo "$df_output"

if [[ $df_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when networksetup fails, got 0"
fi

assert_contains "$df_output" "Could not identify the Wi-Fi hardware interface" "a clear Wi-Fi discovery failure message"
assert_contains "$df_output" "Accessibility permissions" "the Accessibility permission reminder (discovery-failure scenario)"
assert_contains "$df_output" "Prereq checks found issues" "the prerequisite-failure summary (discovery-failure scenario)"

echo "PASS: a networksetup failure produced a clear discovery-failure message and did not exit silently"

# --- Scenario: networksetup succeeds but lists no Wi-Fi/AirPort port -----
echo
echo "== Scenario: networksetup succeeds but reports no Wi-Fi/AirPort hardware port =="

write_networksetup_mock networksetup_noport "$(cat << 'PORTS'
Hardware Port: Ethernet
Device: en0
Ethernet Address: aa:aa:aa:aa:aa:aa

Hardware Port: Bluetooth PAN
Device: en3
Ethernet Address: ee:ee:ee:ee:ee:ee
PORTS
)"
export NETWORKSETUP_BIN="$mock_dir/networksetup_noport"

set +e
np_output="$(run_prereqs 2>&1)"
np_status=$?
set -e

echo "$np_output"

if [[ $np_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when no Wi-Fi/AirPort hardware port is listed, got 0"
fi

assert_contains "$np_output" "Could not identify the Wi-Fi hardware interface" "a clear Wi-Fi discovery failure message (no matching port)"
assert_contains "$np_output" "Accessibility permissions" "the Accessibility permission reminder (no-port scenario)"
assert_contains "$np_output" "Prereq checks found issues" "the prerequisite-failure summary (no-port scenario)"

echo "PASS: a hardware-port listing with no Wi-Fi/AirPort entry produced a clear discovery-failure message"

# --- Scenario: older "AirPort" hardware-port label is recognized ---------
echo
echo "== Scenario: older 'AirPort' hardware-port label is recognized =="

write_networksetup_mock networksetup_airport "$(cat << 'PORTS'
Hardware Port: Ethernet
Device: en0
Ethernet Address: aa:aa:aa:aa:aa:aa

Hardware Port: AirPort
Device: en2
Ethernet Address: ff:ff:ff:ff:ff:ff
PORTS
)"
export NETWORKSETUP_BIN="$mock_dir/networksetup_airport"
: > "$IFCONFIG_LOG"
write_ifconfig_mock en2

set +e
ap_output="$(run_prereqs 2>&1)"
ap_status=$?
set -e

echo "$ap_output"

if [[ $ap_status -ne 0 ]]; then
  fail "expected check_prereqs.sh to exit 0 when the 'AirPort'-labeled device (en2) is active, got $ap_status"
fi

assert_contains "$fail_output" "✓ Bluetooth on" "the Bluetooth success result (failure scenario)"
assert_contains "$fail_output" "Wi-Fi not active" "the Wi-Fi failure message"
assert_contains "$fail_output" "Accessibility permissions" "the Accessibility permission reminder (failure scenario)"
assert_contains "$fail_output" "Prereq checks found issues" "the prerequisite-failure summary"

echo "PASS: the older 'AirPort' hardware-port label is recognized and its device is checked"

# Restore a Wi-Fi-active mock for the remaining Bluetooth-focused scenarios.
write_mock ifconfig '
if [[ "${1:-}" == "en0" ]]; then
  echo "status: active"
fi
'

# --- Scenario 3: Bluetooth explicitly disabled --------------------------
echo
echo "== Scenario: Bluetooth explicitly disabled =="

write_mock defaults '
echo 0
'

set +e
bt_off_output="$(run_prereqs 2>&1)"
bt_off_status=$?
set -e

echo "$bt_off_output"

if [[ $bt_off_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when Bluetooth is explicitly disabled, got 0"
fi

assert_contains "$bt_off_output" "Bluetooth appears off" "the Bluetooth-off message"
assert_not_contains "$bt_off_output" "✓ Bluetooth on" "the Bluetooth success message (disabled scenario)"
assert_contains "$bt_off_output" "Wi-Fi connected" "the Wi-Fi result (Bluetooth-disabled scenario)"
assert_contains "$bt_off_output" "Accessibility permissions" "the Accessibility permission reminder (Bluetooth-disabled scenario)"
assert_contains "$bt_off_output" "Prereq checks found issues" "the prerequisite-failure summary (Bluetooth-disabled scenario)"

echo "PASS: Bluetooth explicitly disabled produced the off message and a nonzero exit"

# --- Scenario 4: Bluetooth preference read fails -------------------------
echo
echo "== Scenario: Bluetooth preference read fails =="

write_mock defaults '
exit 1
'

set +e
bt_fail_output="$(run_prereqs 2>&1)"
bt_fail_status=$?
set -e

echo "$bt_fail_output"

if [[ $bt_fail_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when the Bluetooth preference read fails, got 0"
fi

assert_contains "$bt_fail_output" "Could not determine Bluetooth state" "the Bluetooth-state-unknown message"
assert_not_contains "$bt_fail_output" "✓ Bluetooth on" "the Bluetooth success message (defaults-failure scenario)"
assert_contains "$bt_fail_output" "Wi-Fi connected" "the Wi-Fi result (defaults-failure scenario)"
assert_contains "$bt_fail_output" "Accessibility permissions" "the Accessibility permission reminder (defaults-failure scenario)"
assert_contains "$bt_fail_output" "Prereq checks found issues" "the prerequisite-failure summary (defaults-failure scenario)"

echo "PASS: a failed Bluetooth preference read was treated as unknown, not enabled, and did not exit silently"

# --- Scenario 5: Bluetooth preference read succeeds with no value --------
echo
echo "== Scenario: Bluetooth preference read succeeds but prints no value =="

write_mock defaults '
exit 0
'

set +e
bt_empty_output="$(run_prereqs 2>&1)"
bt_empty_status=$?
set -e

echo "$bt_empty_output"

if [[ $bt_empty_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when the Bluetooth preference read prints no value, got 0"
fi

assert_contains "$bt_empty_output" "Could not determine Bluetooth state" "the Bluetooth-state-unknown message (empty-output scenario)"
assert_not_contains "$bt_empty_output" "✓ Bluetooth on" "the Bluetooth success message (empty-output scenario)"
assert_contains "$bt_empty_output" "Prereq checks found issues" "the prerequisite-failure summary (empty-output scenario)"

echo "PASS: an empty Bluetooth preference read was treated as unknown, not enabled"

# --- Scenario 6: Bluetooth preference read returns an unexpected value ---
echo
echo "== Scenario: Bluetooth preference read returns an unexpected value =="

write_mock defaults '
echo "banana"
'

set +e
bt_bad_output="$(run_prereqs 2>&1)"
bt_bad_status=$?
set -e

echo "$bt_bad_output"

if [[ $bt_bad_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when the Bluetooth preference read returns an unexpected value, got 0"
fi

assert_contains "$bt_bad_output" "Could not determine Bluetooth state" "the Bluetooth-state-unknown message (unexpected-value scenario)"
assert_not_contains "$bt_bad_output" "✓ Bluetooth on" "the Bluetooth success message (unexpected-value scenario)"
assert_contains "$bt_bad_output" "Wi-Fi connected" "the Wi-Fi result (unexpected-value scenario)"
assert_contains "$bt_bad_output" "Accessibility permissions" "the Accessibility permission reminder (unexpected-value scenario)"
assert_contains "$bt_bad_output" "Prereq checks found issues" "the prerequisite-failure summary (unexpected-value scenario)"

echo "PASS: an unexpected Bluetooth preference value was treated as unknown, not enabled"

echo
echo "All check_prereqs.sh regression checks passed."

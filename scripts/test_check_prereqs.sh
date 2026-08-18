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
# 2. "Hard-coded Wi-Fi interface": check_prereqs.sh used to check only
#    en0/en1 for an active Wi-Fi connection. macOS does not guarantee Wi-Fi
#    uses either of those device names, so this produced false negatives
#    (Wi-Fi active on e.g. en7 reported as not connected) and could produce
#    false positives (an unrelated active en0/en1 interface reported as
#    Wi-Fi). The fix dynamically discovers the real Wi-Fi hardware device
#    via the public `networksetup -listallhardwareports` listing.
#
# This test mocks sw_vers, defaults, ifconfig, and networksetup with safe
# test doubles (never touching real system state or network configuration)
# and exercises the script's success, false-positive-prevention, discovery
# -failure, and legacy-label scenarios. It never launches Zoom, Teams,
# AppleScript UI automation, caffeinate, or camera-reset commands.

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
# These guard against the obsolete airport dependency and the hard-coded
# en0/en1 checks reappearing, even if the runtime scenarios below were
# somehow skipped.
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

if grep -Eq 'ifconfig[[:space:]]+en0([[:space:]]|$)' "$prereq_script" \
  || grep -Eq 'ifconfig[[:space:]]+en1([[:space:]]|$)' "$prereq_script"; then
  fail "scripts/check_prereqs.sh still contains a hard-coded 'ifconfig en0'/'ifconfig en1' check"
fi
echo "PASS: no hard-coded ifconfig en0/en1 checks found"

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

write_mock sw_vers '
if [[ "${1:-}" == "-productVersion" ]]; then
  echo "14.5"
fi
'
write_mock defaults '
echo 1
'

# --- Scenario: Wi-Fi on a nonstandard device (en7), en0 is unrelated -----
echo
echo "== Scenario: Wi-Fi on a nonstandard device (en7), en0 is unrelated =="

export IFCONFIG_LOG="$mock_dir/ifconfig_calls.log"
: > "$IFCONFIG_LOG"
write_ifconfig_mock en7
write_networksetup_mock networksetup_success "$(cat << 'PORTS'
Hardware Port: Ethernet
Device: en0
Ethernet Address: aa:aa:aa:aa:aa:aa

Hardware Port: Wi-Fi
Device: en7
Ethernet Address: bb:bb:bb:bb:bb:bb

Hardware Port: Bluetooth PAN
Device: en5
Ethernet Address: cc:cc:cc:cc:cc:cc
PORTS
)"
export NETWORKSETUP_BIN="$mock_dir/networksetup_success"

set +e
output="$(run_prereqs 2>&1)"
status=$?
set -e

echo "$output"

if [[ $status -ne 0 ]]; then
  fail "expected check_prereqs.sh to exit 0 when the dynamically discovered Wi-Fi device (en7) is active, got $status"
fi

assert_contains "$output" "Bluetooth on" "the Bluetooth success result"
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

assert_contains "$ap_output" "Wi-Fi connected" "the Wi-Fi connected result (AirPort label scenario)"
ap_calls="$(cat "$IFCONFIG_LOG" 2>/dev/null || true)"
assert_contains "$ap_calls" "en2" "an ifconfig call for the AirPort-labeled device en2"

echo "PASS: the older 'AirPort' hardware-port label is recognized and its device is checked"

echo
echo "All check_prereqs.sh regression checks passed."

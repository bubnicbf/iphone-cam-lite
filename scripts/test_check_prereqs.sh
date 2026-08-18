#!/usr/bin/env bash
# Regression test for scripts/check_prereqs.sh.
#
# Guards against the "silent premature exit" bug: check_prereqs.sh used to
# call the obsolete private airport utility inside a command substitution
# while set -euo pipefail was active. When that command was missing or
# failed, the script exited immediately after the Bluetooth check and never
# reported Wi-Fi status, the Accessibility reminder, or a final result.
#
# This test mocks sw_vers, defaults, and ifconfig with safe test doubles on
# PATH (never touching real system state) and runs check_prereqs.sh under
# both a success scenario and a Wi-Fi-failure scenario, asserting the full
# expected output sequence in each case. It never launches Zoom, Teams,
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
# These guard against the obsolete airport dependency reappearing, even if
# the runtime scenarios below were somehow skipped.
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

run_prereqs() {
  # Runs check_prereqs.sh with the mock directory first in PATH. Uses
  # 'bash <script>' rather than direct execution so this test does not
  # depend on the script's filesystem executable bit.
  PATH="$mock_dir:$PATH" bash "$prereq_script"
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "expected output to contain $label ('$needle') but it did not"
  fi
}

# --- Scenario 1: macOS Ventura+, Bluetooth on, Wi-Fi active, no airport ---
echo
echo "== Scenario: macOS Ventura+, Bluetooth on, Wi-Fi active =="

write_mock sw_vers '
if [[ "${1:-}" == "-productVersion" ]]; then
  echo "14.5"
fi
'
write_mock defaults '
echo 1
'
write_mock ifconfig '
if [[ "${1:-}" == "en0" ]]; then
  echo "status: active"
fi
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
  fail "expected check_prereqs.sh to exit 0 on the success scenario, got $status"
fi

assert_contains "$output" "Bluetooth on" "the Bluetooth success result"
assert_contains "$output" "Wi-Fi connected" "the Wi-Fi connected result"
assert_contains "$output" "Accessibility permissions" "the Accessibility permission reminder"
assert_contains "$output" "All checks passed" "the final all-checks-passed result"

echo "PASS: success scenario exited 0 with the full expected output"

# --- Scenario 2: Wi-Fi unavailable -------------------------------------
echo
echo "== Scenario: Wi-Fi unavailable =="

write_mock ifconfig '
# No interface reports an active status.
exit 0
'

set +e
fail_output="$(run_prereqs 2>&1)"
fail_status=$?
set -e

echo "$fail_output"

if [[ $fail_status -eq 0 ]]; then
  fail "expected check_prereqs.sh to exit nonzero when Wi-Fi is unavailable, got 0"
fi

assert_contains "$fail_output" "Bluetooth on" "the Bluetooth success result (failure scenario)"
assert_contains "$fail_output" "Wi-Fi not active" "the Wi-Fi failure message"
assert_contains "$fail_output" "Accessibility permissions" "the Accessibility permission reminder (failure scenario)"
assert_contains "$fail_output" "Prereq checks found issues" "the prerequisite-failure summary"

echo "PASS: failure scenario continued past Bluetooth, reported Wi-Fi failure, and exited nonzero"

echo
echo "All check_prereqs.sh regression checks passed."

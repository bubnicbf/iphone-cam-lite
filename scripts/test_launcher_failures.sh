#!/usr/bin/env bash
# Regression test for scripts/start_zoom.sh and scripts/start_teams.sh.
#
# Covers two historical bugs, present in both launchers:
#
# 1. "Suppressed open failure": each launcher ran `open -ga ... || true`, so
#    a failure to launch the application (missing, inaccessible, etc.) was
#    silently swallowed and the script continued as if nothing was wrong.
#
# 2. "Unreported startup timeout": each launcher polled with `pgrep` for a
#    limited number of attempts but never checked whether the loop ended
#    because the process appeared or because the attempt limit was reached.
#    Either way, the script continued to its settling delay and AppleScript
#    device-selection step, so a timeout produced a confusing AppleScript
#    error instead of a clear message about the real cause.
#
# This test mocks open, pgrep, sleep, and osascript with safe test doubles
# in an isolated PATH (never touching real system state, never launching
# Zoom, Teams, or real AppleScript UI automation) and exercises open
# failure, startup timeout, successful start, and invalid configuration
# scenarios against both launchers.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

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

# open: logs its arguments; fails only when OPEN_SHOULD_FAIL=1.
write_mock open '
echo "$*" >> "${OPEN_LOG:-/dev/null}"
if [[ "${OPEN_SHOULD_FAIL:-0}" == "1" ]]; then
  echo "mock open: application not found" >&2
  exit 1
fi
exit 0
'

# pgrep: logs each call and uses a per-scenario counter file so it can fail
# a configurable number of times before succeeding (or never succeed).
write_mock pgrep '
echo "$*" >> "${PGREP_LOG:-/dev/null}"
counter_file="${PGREP_COUNTER_FILE:?PGREP_COUNTER_FILE must be set}"
count=0
[[ -f "$counter_file" ]] && count="$(cat "$counter_file")"
count=$((count+1))
echo "$count" > "$counter_file"
succeed_after="${PGREP_SUCCEED_AFTER:-999999}"
if [[ "$count" -ge "$succeed_after" ]]; then
  exit 0
fi
exit 1
'

# sleep: logs the requested duration and returns immediately (no real delay).
write_mock sleep '
echo "$*" >> "${SLEEP_LOG:-/dev/null}"
exit 0
'

# osascript: logs its arguments and succeeds.
write_mock osascript '
echo "$*" >> "${OSASCRIPT_LOG:-/dev/null}"
exit 0
'

assert_contains() {
  local haystack="$1" needle="$2" label="$3" context="$4"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "[$context] expected output to contain $label ('$needle') but it did not"
  fi
}

count_lines() {
  local file="$1"
  if [[ -f "$file" ]]; then
    wc -l < "$file" | tr -d ' '
  else
    echo 0
  fi
}

# run_launcher invokes the launcher via 'bash <script>' (not direct
# execution) so this test never depends on the script's filesystem
# executable bit, and always points OSASCRIPT_BIN at the mock so the real
# absolute-path osascript is never reached. Does NOT manage set -e itself
# -- callers must wrap the invocation with set +e/set -e so a nonzero exit
# (which every failure scenario expects) does not abort this test script.
run_launcher() {
  local script_path="$1" out_file="$2" err_file="$3"
  PATH="$mock_dir:$PATH" OSASCRIPT_BIN="$mock_dir/osascript" \
    bash "$script_path" > "$out_file" 2> "$err_file"
}

test_launcher() {
  local launcher_name="$1" script_rel="$2" selector_rel="$3"
  local script_path="$repo_root/$script_rel"

  if [[ ! -f "$script_path" ]]; then
    fail "$script_rel not found at $script_path"
  fi

  local scenario_dir open_log pgrep_log pgrep_counter sleep_log osascript_log
  local out_file err_file status out_content err_content

  # --- Scenario: open fails ----------------------------------------------
  echo
  echo "== [$launcher_name] Scenario: open fails =="
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_open_fail"
  mkdir -p "$scenario_dir"
  open_log="$scenario_dir/open.log"; : > "$open_log"
  pgrep_log="$scenario_dir/pgrep.log"; : > "$pgrep_log"
  pgrep_counter="$scenario_dir/pgrep.count"
  sleep_log="$scenario_dir/sleep.log"; : > "$sleep_log"
  osascript_log="$scenario_dir/osascript.log"; : > "$osascript_log"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  set +e
  OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=1 \
    PGREP_LOG="$pgrep_log" PGREP_COUNTER_FILE="$pgrep_counter" PGREP_SUCCEED_AFTER=1 \
    SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" \
    run_launcher "$script_path" "$out_file" "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ $status -eq 0 ]]; then
    fail "[$launcher_name / open-fails] expected nonzero exit when open fails, got 0"
  fi
  assert_contains "$err_content" "$launcher_name" "the application name" "$launcher_name / open-fails (stderr)"
  assert_contains "$err_content" "Failed to launch" "an application-launch-failure message" "$launcher_name / open-fails (stderr)"
  if [[ -s "$pgrep_log" ]]; then
    fail "[$launcher_name / open-fails] pgrep was called after an open failure: $(cat "$pgrep_log")"
  fi
  if [[ -s "$sleep_log" ]]; then
    fail "[$launcher_name / open-fails] sleep was called after an open failure: $(cat "$sleep_log")"
  fi
  if [[ -s "$osascript_log" ]]; then
    fail "[$launcher_name / open-fails] osascript was called after an open failure: $(cat "$osascript_log")"
  fi
  echo "PASS: [$launcher_name] an open failure is reported on stderr and halts before pgrep/sleep/osascript"

  # --- Scenario: process-startup timeout ----------------------------------
  echo
  echo "== [$launcher_name] Scenario: process never appears (timeout) =="
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_timeout"
  mkdir -p "$scenario_dir"
  open_log="$scenario_dir/open.log"; : > "$open_log"
  pgrep_log="$scenario_dir/pgrep.log"; : > "$pgrep_log"
  pgrep_counter="$scenario_dir/pgrep.count"
  sleep_log="$scenario_dir/sleep.log"; : > "$sleep_log"
  osascript_log="$scenario_dir/osascript.log"; : > "$osascript_log"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  set +e
  OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
    PGREP_LOG="$pgrep_log" PGREP_COUNTER_FILE="$pgrep_counter" PGREP_SUCCEED_AFTER=999999 \
    SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" \
    LAUNCHER_ATTEMPTS=3 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    run_launcher "$script_path" "$out_file" "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ $status -eq 0 ]]; then
    fail "[$launcher_name / timeout] expected nonzero exit on a process-startup timeout, got 0"
  fi
  if [[ "$(count_lines "$open_log")" -ne 1 ]]; then
    fail "[$launcher_name / timeout] expected open to be called exactly once, got $(count_lines "$open_log")"
  fi
  if [[ "$(count_lines "$pgrep_log")" -ne 3 ]]; then
    fail "[$launcher_name / timeout] expected pgrep to be called 3 times (the configured attempt limit), got $(count_lines "$pgrep_log")"
  fi
  assert_contains "$err_content" "$launcher_name" "the application name" "$launcher_name / timeout (stderr)"
  assert_contains "$err_content" "did not start" "a startup-timeout message" "$launcher_name / timeout (stderr)"
  if [[ -s "$osascript_log" ]]; then
    fail "[$launcher_name / timeout] osascript was called after a startup timeout: $(cat "$osascript_log")"
  fi
  if [[ "$(count_lines "$sleep_log")" -ne 3 ]]; then
    fail "[$launcher_name / timeout] expected exactly 3 sleep calls (polling only, no settling delay), got $(count_lines "$sleep_log"): $(cat "$sleep_log")"
  fi
  echo "PASS: [$launcher_name] a startup timeout is reported on stderr and skips the settling delay and osascript"

  # --- Scenario: successful start ------------------------------------------
  echo
  echo "== [$launcher_name] Scenario: process appears before the attempt limit =="
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_success"
  mkdir -p "$scenario_dir"
  open_log="$scenario_dir/open.log"; : > "$open_log"
  pgrep_log="$scenario_dir/pgrep.log"; : > "$pgrep_log"
  pgrep_counter="$scenario_dir/pgrep.count"
  sleep_log="$scenario_dir/sleep.log"; : > "$sleep_log"
  osascript_log="$scenario_dir/osascript.log"; : > "$osascript_log"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  set +e
  OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
    PGREP_LOG="$pgrep_log" PGREP_COUNTER_FILE="$pgrep_counter" PGREP_SUCCEED_AFTER=3 \
    SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" \
    LAUNCHER_ATTEMPTS=10 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    run_launcher "$script_path" "$out_file" "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ $status -ne 0 ]]; then
    fail "[$launcher_name / success] expected exit 0 when the process appears before the attempt limit, got $status (stderr: $err_content)"
  fi
  if [[ "$(count_lines "$pgrep_log")" -ne 3 ]]; then
    fail "[$launcher_name / success] expected polling to stop as soon as the process was found (3 pgrep calls), got $(count_lines "$pgrep_log")"
  fi
  if [[ "$(count_lines "$sleep_log")" -ne 3 ]]; then
    fail "[$launcher_name / success] expected 2 polling sleeps plus 1 settling delay (3 total), got $(count_lines "$sleep_log"): $(cat "$sleep_log")"
  fi
  if [[ "$(count_lines "$osascript_log")" -ne 1 ]]; then
    fail "[$launcher_name / success] expected osascript to be invoked exactly once, got $(count_lines "$osascript_log")"
  fi
  assert_contains "$(cat "$osascript_log")" "$selector_rel" "the correct AppleScript selector" "$launcher_name / success"
  echo "PASS: [$launcher_name] a successful start polls until found, runs the settling delay, and invokes $selector_rel exactly once"

  # --- Scenario: invalid LAUNCHER_ATTEMPTS override ------------------------
  echo
  echo "== [$launcher_name] Scenario: invalid LAUNCHER_ATTEMPTS override =="
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_invalid_attempts"
  mkdir -p "$scenario_dir"
  open_log="$scenario_dir/open.log"; : > "$open_log"
  pgrep_log="$scenario_dir/pgrep.log"; : > "$pgrep_log"
  pgrep_counter="$scenario_dir/pgrep.count"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  set +e
  OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
    PGREP_LOG="$pgrep_log" PGREP_COUNTER_FILE="$pgrep_counter" PGREP_SUCCEED_AFTER=999999 \
    LAUNCHER_ATTEMPTS="not-a-number" \
    run_launcher "$script_path" "$out_file" "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ $status -eq 0 ]]; then
    fail "[$launcher_name / invalid-attempts] expected nonzero exit for an invalid LAUNCHER_ATTEMPTS value, got 0"
  fi
  assert_contains "$err_content" "Invalid LAUNCHER_ATTEMPTS" "a clear configuration error" "$launcher_name / invalid-attempts (stderr)"
  if [[ -s "$open_log" ]]; then
    fail "[$launcher_name / invalid-attempts] open was called even though LAUNCHER_ATTEMPTS was invalid: $(cat "$open_log")"
  fi
  if [[ -s "$pgrep_log" ]]; then
    fail "[$launcher_name / invalid-attempts] pgrep was called even though LAUNCHER_ATTEMPTS was invalid: $(cat "$pgrep_log")"
  fi
  echo "PASS: [$launcher_name] an invalid LAUNCHER_ATTEMPTS override is rejected with a clear error before launching anything"
}

test_launcher "Zoom" "scripts/start_zoom.sh" "scripts/select_zoom_camera.scpt"
test_launcher "Microsoft Teams" "scripts/start_teams.sh" "scripts/select_teams_camera.scpt"

echo
echo "All launcher regression checks passed."

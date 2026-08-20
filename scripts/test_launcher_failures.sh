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

# Exact-matching-aware mode (opt in with PGREP_MODE=exact), used by the
# process-matching regression scenarios further down this file. It is
# args-aware: it distinguishes a broad "-f" (full command-line) search
# from an exact "-x" (executable-name) search, so tests can prove the
# launcher only ever performs the latter. When PGREP_MODE is unset it
# falls through to the original argument-agnostic counter behavior below,
# which the failure/timeout/success/invalid-attempts scenarios above rely
# on unchanged.
if [[ "${PGREP_MODE:-counter}" == "exact" ]]; then
  opt="${1:-}"
  name="${2:-}"
  if [[ "$opt" == "-f" ]]; then
    # Simulates an unrelated process whose full command line happens to
    # contain the app name -- only ever "matches" if a caller explicitly
    # asks this mock to simulate that broad, false-positive-prone search.
    if [[ "${PGREP_F_SUCCEEDS:-0}" == "1" ]]; then
      exit 0
    fi
    exit 1
  fi
  if [[ "$opt" == "-x" ]]; then
    counter_file="${PGREP_COUNTER_FILE:?PGREP_COUNTER_FILE must be set}"
    count=0
    [[ -f "$counter_file" ]] && count="$(cat "$counter_file")"
    count=$((count+1))
    echo "$count" > "$counter_file"
    if [[ "$name" == "${PGREP_EXACT_MATCH_NAME:-__no_match__}" ]] \
      && [[ "$count" -ge "${PGREP_EXACT_SUCCEED_AFTER:-999999}" ]]; then
      exit 0
    fi
    exit 1
  fi
  # Any other invocation shape is never treated as a match.
  exit 1
fi

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
# Opt-in, precise argument recording used by the resource-path regression
# scenarios: $# (the real argument COUNT) and each argument on its own
# line, so a quoting/splitting bug involving spaces in a path can be
# detected even though $* alone would obscure it.
if [[ -n "${OSASCRIPT_ARGC_LOG:-}" ]]; then
  echo "$#" >> "$OSASCRIPT_ARGC_LOG"
fi
if [[ -n "${OSASCRIPT_ARGS_FILE:-}" ]]; then
  printf "%s\n" "$@" > "$OSASCRIPT_ARGS_FILE"
fi
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

# test_exact_process_matching covers the exact-executable-name matching
# fix: it proves the launcher can no longer be fooled by an unrelated
# process whose full command line merely contains the app name (the
# historical `pgrep -f` false-positive bug), and that it correctly
# recognizes only its real, exact application executable.
test_exact_process_matching() {
  local launcher_name="$1" script_rel="$2" selector_rel="$3" exact_name="$4"
  local script_path="$repo_root/$script_rel"

  if [[ ! -f "$script_path" ]]; then
    fail "$script_rel not found at $script_path"
  fi

  local scenario_dir open_log pgrep_log pgrep_counter sleep_log osascript_log
  local out_file err_file status out_content err_content

  # --- Scenario: unrelated command line is not mistaken for the app ------
  echo
  echo "== [$launcher_name] Scenario: unrelated command line contains the app name (pgrep -f false positive) =="
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_unrelated_cmdline"
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
    PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=1 \
    PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=999999 \
    SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" \
    LAUNCHER_ATTEMPTS=3 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    run_launcher "$script_path" "$out_file" "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"
  echo "pgrep calls: $(cat "$pgrep_log")"

  if [[ $status -eq 0 ]]; then
    fail "[$launcher_name / unrelated-cmdline] expected nonzero exit when only an unrelated command line contains the app name, got 0"
  fi
  assert_contains "$err_content" "did not start" "a startup-timeout message" "$launcher_name / unrelated-cmdline (stderr)"
  if [[ -s "$osascript_log" ]]; then
    fail "[$launcher_name / unrelated-cmdline] the selector was invoked even though the real application never started: $(cat "$osascript_log")"
  fi
  if [[ "$(count_lines "$sleep_log")" -ne 3 ]]; then
    fail "[$launcher_name / unrelated-cmdline] expected exactly 3 polling sleeps and no settling-delay sleep, got $(count_lines "$sleep_log"): $(cat "$sleep_log")"
  fi
  if grep -q -- '-f' "$pgrep_log"; then
    fail "[$launcher_name / unrelated-cmdline] a pgrep call used -f (broad command-line search): $(cat "$pgrep_log")"
  fi
  echo "PASS: [$launcher_name] an unrelated process whose command line contains the app name is not mistaken for the real application, and the selector is never invoked"

  # --- Scenario: exact application executable is recognized --------------
  echo
  echo "== [$launcher_name] Scenario: exact application executable ($exact_name) is recognized =="
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_exact_match"
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
    PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=0 \
    PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=3 \
    SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" \
    LAUNCHER_ATTEMPTS=10 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    run_launcher "$script_path" "$out_file" "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"
  echo "pgrep calls: $(cat "$pgrep_log")"

  if [[ $status -ne 0 ]]; then
    fail "[$launcher_name / exact-match] expected exit 0 once the exact executable is found, got $status (stderr: $err_content)"
  fi
  if [[ "$(count_lines "$pgrep_log")" -ne 3 ]]; then
    fail "[$launcher_name / exact-match] expected polling to stop as soon as the exact executable was found (3 pgrep calls), got $(count_lines "$pgrep_log")"
  fi
  if [[ "$(count_lines "$osascript_log")" -ne 1 ]]; then
    fail "[$launcher_name / exact-match] expected osascript to be invoked exactly once, got $(count_lines "$osascript_log")"
  fi
  assert_contains "$(cat "$osascript_log")" "$selector_rel" "the correct AppleScript selector" "$launcher_name / exact-match"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" != "-x $exact_name" ]]; then
      fail "[$launcher_name / exact-match] expected every pgrep call to be exactly '-x $exact_name' (never a helper name, substring, or -f search), but saw: $line"
    fi
  done < "$pgrep_log"
  echo "PASS: [$launcher_name] the exact application executable ($exact_name) is recognized, polling stops immediately, and $selector_rel is invoked exactly once; no helper, substring, or broad-search name ever satisfies the check"
}

test_exact_process_matching "Zoom" "scripts/start_zoom.sh" "scripts/select_zoom_camera.scpt" "zoom.us"
test_exact_process_matching "Microsoft Teams" "scripts/start_teams.sh" "scripts/select_teams_camera.scpt" "MSTeams"

# --- Static assertions: production launchers never use broad pgrep -f ----
echo
echo "== Static checks: production launchers use only exact pgrep matching =="
for launcher_script in "scripts/start_zoom.sh" "scripts/start_teams.sh"; do
  launcher_path="$repo_root/$launcher_script"
  # Only inspect actual code, not comment lines that merely discuss the
  # historical "pgrep -f" bug in prose.
  code_only="$(grep -v -E '^[[:space:]]*#' "$launcher_path")"
  if echo "$code_only" | grep -q -- 'pgrep -f'; then
    fail "[static / $launcher_script] found a live pgrep invocation using -f: $(echo "$code_only" | grep -- 'pgrep -f')"
  fi
  if ! echo "$code_only" | grep -q -- 'pgrep -x'; then
    fail "[static / $launcher_script] expected at least one 'pgrep -x' (exact match) invocation, found none"
  fi
done
if ! grep -q '"zoom.us"' "$repo_root/scripts/start_zoom.sh"; then
  fail "[static / start_zoom.sh] expected the exact executable name \"zoom.us\" to appear in the script"
fi
if ! grep -q '"MSTeams"' "$repo_root/scripts/start_teams.sh"; then
  fail "[static / start_teams.sh] expected the exact executable name \"MSTeams\" to appear in the script"
fi
if grep -q 'pgrep -x "\$APP_NAME"' "$repo_root/scripts/start_teams.sh"; then
  fail "[static / start_teams.sh] the display name \$APP_NAME (\"Microsoft Teams\") must not be used as the exact process-match pattern -- it is not the real executable name"
fi
echo "PASS: [static] no production launcher contains pgrep -f, both use pgrep -x with their documented exact executable names, and display names are not substituted for executable names"

echo
echo "All launcher regression checks passed."
# test_resource_resolution covers the script-location resource-resolution
# fix: it proves each launcher finds its AppleScript selector via its own
# script location (BASH_SOURCE), not the caller's current working
# directory -- including when invoked by absolute path from completely
# outside the repository, and when the caller's directory path contains
# spaces.
test_resource_resolution() {
  local launcher_name="$1" script_rel="$2" selector_rel="$3" exact_name="$4"
  local script_path="$repo_root/$script_rel"
  local expected_selector="$repo_root/$selector_rel"

  # --- Scenario: invoked by absolute path from outside the repository ----
  echo
  echo "== [$launcher_name] Scenario: invoked by absolute path from a directory outside the repo =="
  local scenario_dir outside_dir open_log pgrep_log pgrep_counter sleep_log
  local osascript_log osascript_argc_log osascript_args_file out_file err_file
  local status pwd_before pwd_after
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_outside_cwd"
  mkdir -p "$scenario_dir"
  outside_dir="$(mktemp -d)"
  open_log="$scenario_dir/open.log"; : > "$open_log"
  pgrep_log="$scenario_dir/pgrep.log"; : > "$pgrep_log"
  pgrep_counter="$scenario_dir/pgrep.count"
  sleep_log="$scenario_dir/sleep.log"; : > "$sleep_log"
  osascript_log="$scenario_dir/osascript.log"; : > "$osascript_log"
  osascript_argc_log="$scenario_dir/osascript_argc.log"; : > "$osascript_argc_log"
  osascript_args_file="$scenario_dir/osascript_args.txt"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  pwd_before="$(cd "$outside_dir" && pwd)"
  cd "$outside_dir"
  set +e
  OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
    PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=0 \
    PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=1 \
    SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" OSASCRIPT_ARGC_LOG="$osascript_argc_log" OSASCRIPT_ARGS_FILE="$osascript_args_file" \
    LAUNCHER_ATTEMPTS=5 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    PATH="$mock_dir:$PATH" OSASCRIPT_BIN="$mock_dir/osascript" \
    bash "$script_path" > "$out_file" 2> "$err_file"
  status=$?
  set -e
  pwd_after="$(pwd)"
  cd "$repo_root"
  rm -rf "$outside_dir"

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"
  echo "osascript args file: $(cat "$osascript_args_file" 2>/dev/null || true)"

  if [[ $status -ne 0 ]]; then
    fail "[$launcher_name / outside-cwd] expected exit 0 when invoked by absolute path from outside the repo, got $status (stderr: $err_content)"
  fi
  if [[ "$pwd_before" != "$pwd_after" ]]; then
    fail "[$launcher_name / outside-cwd] the caller's working directory changed from '$pwd_before' to '$pwd_after'"
  fi
  local recorded_selector
  recorded_selector="$(head -n 1 "$osascript_args_file" 2>/dev/null || true)"
  if [[ "$recorded_selector" != "$expected_selector" ]]; then
    fail "[$launcher_name / outside-cwd] expected osascript's first argument to be the absolute selector path '$expected_selector', got '$recorded_selector'"
  fi
  case "$recorded_selector" in
    scripts/*)
      fail "[$launcher_name / outside-cwd] osascript received a caller-relative scripts/ path instead of an absolute one: $recorded_selector"
      ;;
  esac
  if [[ ! -f "$recorded_selector" || ! -r "$recorded_selector" ]]; then
    fail "[$launcher_name / outside-cwd] the selector path passed to osascript does not identify an existing readable file: $recorded_selector"
  fi
  echo "PASS: [$launcher_name] invoked by absolute path from an unrelated directory, the launcher still resolves the same absolute selector path ($expected_selector) and leaves the caller's working directory unchanged"

  # --- Scenario: caller directory path contains spaces ---------------------
  echo
  echo "== [$launcher_name] Scenario: caller directory path contains spaces =="
  local spacey_parent spacey_dir
  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_spacey_cwd"
  mkdir -p "$scenario_dir"
  spacey_parent="$(mktemp -d)"
  spacey_dir="$spacey_parent/dir with spaces"
  mkdir -p "$spacey_dir"
  open_log="$scenario_dir/open.log"; : > "$open_log"
  pgrep_log="$scenario_dir/pgrep.log"; : > "$pgrep_log"
  pgrep_counter="$scenario_dir/pgrep.count"
  sleep_log="$scenario_dir/sleep.log"; : > "$sleep_log"
  osascript_log="$scenario_dir/osascript.log"; : > "$osascript_log"
  osascript_argc_log="$scenario_dir/osascript_argc.log"; : > "$osascript_argc_log"
  osascript_args_file="$scenario_dir/osascript_args.txt"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  cd "$spacey_dir"
  set +e
  OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
    PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=0 \
    PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=1 \
    SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" OSASCRIPT_ARGC_LOG="$osascript_argc_log" OSASCRIPT_ARGS_FILE="$osascript_args_file" \
    LAUNCHER_ATTEMPTS=5 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    PATH="$mock_dir:$PATH" OSASCRIPT_BIN="$mock_dir/osascript" \
    bash "$script_path" > "$out_file" 2> "$err_file"
  status=$?
  set -e
  cd "$repo_root"
  rm -rf "$spacey_parent"

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ $status -ne 0 ]]; then
    fail "[$launcher_name / spacey-cwd] expected exit 0 when the caller's directory path contains spaces, got $status (stderr: $err_content)"
  fi
  local argc expected_argc
  case "$launcher_name" in
    Zoom) expected_argc=8 ;;    # selector, camera, mic, 5 Zoom UI-label args
    *) expected_argc=7 ;;       # selector, camera, mic, 4 Teams UI-label args
  esac
  argc="$(cat "$osascript_argc_log" 2>/dev/null || true)"
  if [[ "$argc" != "$expected_argc" ]]; then
    fail "[$launcher_name / spacey-cwd] expected osascript to receive exactly $expected_argc arguments (selector, camera name, microphone name, and documented UI-label overrides), got argc='$argc' (a quoting bug would split or merge arguments)"
  fi
  recorded_selector="$(head -n 1 "$osascript_args_file" 2>/dev/null || true)"
  if [[ "$recorded_selector" != "$expected_selector" ]]; then
    fail "[$launcher_name / spacey-cwd] expected osascript's first argument to be '$expected_selector', got '$recorded_selector'"
  fi
  echo "PASS: [$launcher_name] a caller directory whose path contains spaces does not cause argument splitting; osascript still receives exactly $expected_argc correct arguments, the first being the absolute selector path"
}

test_resource_resolution "Zoom" "scripts/start_zoom.sh" "scripts/select_zoom_camera.scpt" "zoom.us"
test_resource_resolution "Microsoft Teams" "scripts/start_teams.sh" "scripts/select_teams_camera.scpt" "MSTeams"

# test_missing_resource covers the missing/unreadable-selector guard. It
# copies only the launcher script into an isolated fixture directory (with
# no .scpt file present), so the guard is proven without ever touching,
# deleting, or renaming the real repository resources.
test_missing_resource() {
  local launcher_name="$1" script_rel="$2"
  local script_path="$repo_root/$script_rel"

  echo
  echo "== [$launcher_name] Scenario: expected selector resource is missing =="
  local fixture_dir open_log osascript_log out_file err_file status
  fixture_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_missing_selector"
  mkdir -p "$fixture_dir/scripts"
  cp "$script_path" "$fixture_dir/scripts/$(basename "$script_path")"
  chmod +x "$fixture_dir/scripts/$(basename "$script_path")"
  # Deliberately do NOT copy any .scpt file into the fixture.

  open_log="$fixture_dir/open.log"; : > "$open_log"
  osascript_log="$fixture_dir/osascript.log"; : > "$osascript_log"
  out_file="$fixture_dir/stdout.log"
  err_file="$fixture_dir/stderr.log"

  set +e
  OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
    OSASCRIPT_LOG="$osascript_log" \
    PATH="$mock_dir:$PATH" OSASCRIPT_BIN="$mock_dir/osascript" \
    bash "$fixture_dir/scripts/$(basename "$script_path")" > "$out_file" 2> "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ $status -eq 0 ]]; then
    fail "[$launcher_name / missing-selector] expected nonzero exit when the selector resource is missing, got 0"
  fi
  assert_contains "$err_content" "not found or not readable" "a clear missing-resource error" "$launcher_name / missing-selector (stderr)"
  assert_contains "$err_content" ".scpt" "the expected selector filename" "$launcher_name / missing-selector (stderr)"
  if [[ -s "$osascript_log" ]]; then
    fail "[$launcher_name / missing-selector] osascript was invoked even though the selector is missing: $(cat "$osascript_log")"
  fi
  if [[ -s "$open_log" ]]; then
    fail "[$launcher_name / missing-selector] the application was launched even though the selector is missing (resource validation should happen before launch): $(cat "$open_log")"
  fi
  echo "PASS: [$launcher_name] a missing selector resource is reported clearly, and neither the application nor osascript is invoked"
}

test_missing_resource "Zoom" "scripts/start_zoom.sh"
test_missing_resource "Microsoft Teams" "scripts/start_teams.sh"

# --- Static assertions: production launchers resolve resources from their
# --- own script location, not the caller's working directory -------------
echo
echo "== Static checks: production launchers resolve resources from script location =="
for launcher_script in "scripts/start_zoom.sh" "scripts/start_teams.sh"; do
  launcher_path="$repo_root/$launcher_script"
  if ! grep -q 'BASH_SOURCE' "$launcher_path"; then
    fail "[static / $launcher_script] expected script-directory resolution via BASH_SOURCE, found none"
  fi
  if grep -q '"\$OSASCRIPT_BIN" scripts/select_' "$launcher_path"; then
    fail "[static / $launcher_script] still invokes osascript with a bare caller-relative scripts/select_*.scpt path"
  fi
  if ! grep -q '"\$OSASCRIPT_BIN" "\$SELECTOR_PATH"' "$launcher_path"; then
    fail "[static / $launcher_script] expected a quoted \"\$OSASCRIPT_BIN\" \"\$SELECTOR_PATH\" invocation"
  fi
done
# Only inspect actual code, not comment lines that merely discuss the
# selector filename in prose.
zoom_code_only="$(grep -v -E '^[[:space:]]*#' "$repo_root/scripts/start_zoom.sh")"
if echo "$zoom_code_only" | grep -q 'scripts/select_zoom_camera\.scpt'; then
  fail "[static / start_zoom.sh] a bare caller-relative scripts/select_zoom_camera.scpt reference remains in live code"
fi
teams_code_only="$(grep -v -E '^[[:space:]]*#' "$repo_root/scripts/start_teams.sh")"
if echo "$teams_code_only" | grep -q 'scripts/select_teams_camera\.scpt'; then
  fail "[static / start_teams.sh] a bare caller-relative scripts/select_teams_camera.scpt reference remains in live code"
fi
echo "PASS: [static] both launchers resolve their script directory from BASH_SOURCE, no bare caller-relative selector path remains, and the selector invocation is quoted"

echo
echo "All launcher regression checks passed."
# test_device_name_configuration covers the runtime CAMERA_NAME /
# MICROPHONE_NAME configuration fix: it proves each launcher resolves the
# documented defaults when the variables are unset or empty, passes a
# custom value (including names with spaces, punctuation, apostrophes, and
# Unicode characters) through to osascript as exactly one argument each,
# and that CAMERA_NAME and MICROPHONE_NAME can be overridden independently
# of each other.
test_device_name_configuration() {
  local launcher_name="$1" script_rel="$2" exact_name="$3"
  local script_path="$repo_root/$script_rel"

  run_device_name_scenario() {
    local scenario_label="$1" camera_env="$2" camera_is_set="$3" mic_env="$4" mic_is_set="$5"
    local expected_camera="$6" expected_mic="$7"
    local scenario_dir open_log pgrep_log pgrep_counter sleep_log
    local osascript_log osascript_argc_log osascript_args_file out_file err_file status

    scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_devname_$(echo "$scenario_label" | tr ' ' '_')"
    mkdir -p "$scenario_dir"
    open_log="$scenario_dir/open.log"; : > "$open_log"
    pgrep_log="$scenario_dir/pgrep.log"; : > "$pgrep_log"
    pgrep_counter="$scenario_dir/pgrep.count"
    sleep_log="$scenario_dir/sleep.log"; : > "$sleep_log"
    osascript_log="$scenario_dir/osascript.log"; : > "$osascript_log"
    osascript_argc_log="$scenario_dir/osascript_argc.log"; : > "$osascript_argc_log"
    osascript_args_file="$scenario_dir/osascript_args.txt"
    out_file="$scenario_dir/stdout.log"
    err_file="$scenario_dir/stderr.log"

    set +e
    if [[ "$camera_is_set" == "1" && "$mic_is_set" == "1" ]]; then
      CAMERA_NAME="$camera_env" MICROPHONE_NAME="$mic_env" \
        OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
        PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=0 \
        PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=1 \
        SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" OSASCRIPT_ARGC_LOG="$osascript_argc_log" OSASCRIPT_ARGS_FILE="$osascript_args_file" \
        LAUNCHER_ATTEMPTS=5 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
        run_launcher "$script_path" "$out_file" "$err_file"
    elif [[ "$camera_is_set" == "1" ]]; then
      CAMERA_NAME="$camera_env" \
        OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
        PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=0 \
        PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=1 \
        SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" OSASCRIPT_ARGC_LOG="$osascript_argc_log" OSASCRIPT_ARGS_FILE="$osascript_args_file" \
        LAUNCHER_ATTEMPTS=5 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
        run_launcher "$script_path" "$out_file" "$err_file"
    elif [[ "$mic_is_set" == "1" ]]; then
      MICROPHONE_NAME="$mic_env" \
        OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
        PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=0 \
        PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=1 \
        SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" OSASCRIPT_ARGC_LOG="$osascript_argc_log" OSASCRIPT_ARGS_FILE="$osascript_args_file" \
        LAUNCHER_ATTEMPTS=5 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
        run_launcher "$script_path" "$out_file" "$err_file"
    else
      OPEN_LOG="$open_log" OPEN_SHOULD_FAIL=0 \
        PGREP_LOG="$pgrep_log" PGREP_MODE=exact PGREP_F_SUCCEEDS=0 \
        PGREP_COUNTER_FILE="$pgrep_counter" PGREP_EXACT_MATCH_NAME="$exact_name" PGREP_EXACT_SUCCEED_AFTER=1 \
        SLEEP_LOG="$sleep_log" OSASCRIPT_LOG="$osascript_log" OSASCRIPT_ARGC_LOG="$osascript_argc_log" OSASCRIPT_ARGS_FILE="$osascript_args_file" \
        LAUNCHER_ATTEMPTS=5 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
        run_launcher "$script_path" "$out_file" "$err_file"
    fi
    status=$?
    set -e

    out_content="$(cat "$out_file")"; err_content="$(cat "$err_file")"
    echo "stdout: $out_content"
    echo "stderr: $err_content"

    if [[ $status -ne 0 ]]; then
      fail "[$launcher_name / devname-$scenario_label] expected exit 0, got $status (stderr: $err_content)"
    fi
    if [[ "$(count_lines "$osascript_log")" -ne 1 ]]; then
      fail "[$launcher_name / devname-$scenario_label] expected osascript to be invoked exactly once, got $(count_lines "$osascript_log")"
    fi
    local argc expected_argc
    case "$launcher_name" in
      Zoom) expected_argc=8 ;;    # selector, camera, mic, 5 Zoom UI-label args
      *) expected_argc=7 ;;       # selector, camera, mic, 4 Teams UI-label args
    esac
    argc="$(cat "$osascript_argc_log" 2>/dev/null || true)"
    if [[ "$argc" != "$expected_argc" ]]; then
      fail "[$launcher_name / devname-$scenario_label] expected osascript to receive exactly $expected_argc arguments (selector, camera, microphone, and documented UI-label overrides), got argc='$argc'"
    fi
    local got_selector got_camera got_mic
    got_selector="$(sed -n '1p' "$osascript_args_file")"
    got_camera="$(sed -n '2p' "$osascript_args_file")"
    got_mic="$(sed -n '3p' "$osascript_args_file")"
    case "$got_selector" in
      */select_*.scpt) : ;;
      *) fail "[$launcher_name / devname-$scenario_label] expected argument 1 to be the selector path, got '$got_selector'" ;;
    esac
    if [[ "$got_camera" != "$expected_camera" ]]; then
      fail "[$launcher_name / devname-$scenario_label] expected the camera argument to be exactly '$expected_camera', got '$got_camera'"
    fi
    if [[ "$got_mic" != "$expected_mic" ]]; then
      fail "[$launcher_name / devname-$scenario_label] expected the microphone argument to be exactly '$expected_mic', got '$got_mic'"
    fi
    echo "PASS: [$launcher_name] devname-$scenario_label: camera='$got_camera' microphone='$got_mic' (exactly $expected_argc arguments, selector first)"
  }

  echo
  echo "== [$launcher_name] Scenario: default device names (CAMERA_NAME/MICROPHONE_NAME unset) =="
  run_device_name_scenario "default" "" 0 "" 0 "iPhone Camera" "iPhone Microphone"

  echo
  echo "== [$launcher_name] Scenario: custom device names with spaces and punctuation =="
  run_device_name_scenario "custom" "Benjamin's iPhone Camera" 1 "Studio USB Mic (Desk)" 1 \
    "Benjamin's iPhone Camera" "Studio USB Mic (Desk)"

  echo
  echo "== [$launcher_name] Scenario: Unicode device names =="
  run_device_name_scenario "unicode" "Bénjàmïn's Café Caméra 📷" 1 "Míc à côté (принтер)" 1 \
    "Bénjàmïn's Café Caméra 📷" "Míc à côté (принтер)"

  echo
  echo "== [$launcher_name] Scenario: only CAMERA_NAME overridden =="
  run_device_name_scenario "camera-only" "Conference Room Camera" 1 "" 0 \
    "Conference Room Camera" "iPhone Microphone"

  echo
  echo "== [$launcher_name] Scenario: only MICROPHONE_NAME overridden =="
  run_device_name_scenario "mic-only" "" 0 "Lapel Mic" 1 \
    "iPhone Camera" "Lapel Mic"

  echo
  echo "== [$launcher_name] Scenario: both variables set to an empty string fall back to defaults =="
  run_device_name_scenario "empty" "" 1 "" 1 "iPhone Camera" "iPhone Microphone"

  unset -f run_device_name_scenario
}

test_device_name_configuration "Zoom" "scripts/start_zoom.sh" "zoom.us"
test_device_name_configuration "Microsoft Teams" "scripts/start_teams.sh" "MSTeams"

# --- Static assertions: selectors accept configurable device names -------
echo
echo "== Static checks: selectors accept configurable camera/microphone names =="
for selector_script in "scripts/select_zoom_camera.scpt" "scripts/select_teams_camera.scpt"; do
  selector_path="$repo_root/$selector_script"
  if ! grep -q '^on run argv' "$selector_path"; then
    fail "[static / $selector_script] expected a run handler accepting arguments (on run argv), found none"
  fi
  if ! grep -q 'resolveArg(argv, 1,' "$selector_path"; then
    fail "[static / $selector_script] expected argument 1 (resolveArg(argv, 1, ...)) to be read as the camera name"
  fi
  if ! grep -q 'resolveArg(argv, 2,' "$selector_path"; then
    fail "[static / $selector_script] expected argument 2 (resolveArg(argv, 2, ...)) to be read as the microphone name"
  fi
  if ! grep -q 'property desiredCamera : "iPhone Camera"' "$selector_path"; then
    fail "[static / $selector_script] expected the default camera name property (iPhone Camera) to be retained"
  fi
  if ! grep -q 'property desiredMic : "iPhone Microphone"' "$selector_path"; then
    fail "[static / $selector_script] expected the default microphone name property (iPhone Microphone) to be retained"
  fi
  if ! grep -qE '(selectDeviceFromCandidates|pickMenuItem)\([^)]*desiredCamera' "$selector_path"; then
    fail "[static / $selector_script] expected the resolved camera name to be passed into a device-selection handler (selectDeviceFromCandidates or pickMenuItem), not just declared"
  fi
done
for launcher_script in "scripts/start_zoom.sh" "scripts/start_teams.sh"; do
  launcher_path="$repo_root/$launcher_script"
  if ! grep -q '"\$OSASCRIPT_BIN" "\$SELECTOR_PATH" "\$CAMERA_NAME" "\$MICROPHONE_NAME"' "$launcher_path"; then
    fail "[static / $launcher_script] expected osascript to be invoked with the selector path plus the two resolved device names"
  fi
  launcher_code_only="$(grep -v -E '^[[:space:]]*#' "$launcher_path")"
  if echo "$launcher_code_only" | grep -qw 'eval'; then
    fail "[static / $launcher_script] must not use eval"
  fi
done
echo "PASS: [static] both selectors define an argument-accepting run handler, read the camera/microphone names in the documented order, retain their default properties, and both launchers pass the two resolved names as distinct osascript arguments without eval"

echo
echo "All launcher regression checks passed."

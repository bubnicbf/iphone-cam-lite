#!/usr/bin/env bash
# Regression coverage for the device-selection confirmation fix: the Zoom
# and Teams selectors must exit successfully only once both the requested
# camera and microphone have actually been read back and confirmed
# selected via the app's own accessibility state -- never merely because a
# click command completed without throwing. This file never launches real
# Zoom, Teams, or System Events automation; it only performs static source
# assertions covering the required confirmation scenarios, an osacompile
# syntax check (if available), and mock-based shell-launcher propagation
# checks for both an unconfirmed-selection failure and a confirmed-success
# case.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

mock_dir="$(mktemp -d)"
trap 'rm -rf "$mock_dir"' EXIT

write_mock() {
  local name="$1" body="$2"
  cat > "$mock_dir/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$mock_dir/$name"
}

ZOOM_SCPT="$repo_root/scripts/select_zoom_camera.scpt"
TEAMS_SCPT="$repo_root/scripts/select_teams_camera.scpt"

assert_source_contains() {
  local file="$1" pattern="$2" scenario="$3"
  if ! grep -qF "$pattern" "$file"; then
    fail "[$scenario] expected pattern not found in $(basename "$file"): $pattern"
  fi
}

assert_source_not_contains() {
  local file="$1" pattern="$2" scenario="$3"
  if grep -qF "$pattern" "$file"; then
    fail "[$scenario] found a pattern that should not be present in $(basename "$file"): $pattern"
  fi
}

# ===========================================================================
# Section A: static core-contract assertions.
# ===========================================================================
echo "== Static checks: confirmation core contract =="

for pair in "$ZOOM_SCPT:Zoom" "$TEAMS_SCPT:Teams"; do
  file="${pair%%:*}"
  label="${pair##*:}"

  # Independent camera/microphone confirmation tracking, each with its own
  # diagnostic -- never a single combined flag.
  assert_source_contains "$file" 'set camPicked to false' "independent tracking / $label"
  assert_source_contains "$file" 'set micPicked to false' "independent tracking / $label"
  assert_source_contains "$file" 'set camDiagnostic to' "independent diagnostic / $label"
  assert_source_contains "$file" 'set micDiagnostic to' "independent diagnostic / $label"

  # Final success requires both confirmed -- the exact guard that makes
  # partial or single-device success impossible.
  assert_source_contains "$file" 'if camPicked and micPicked then' "both required / $label"

  # A bounded, documented poll -- never an indefinite wait -- backs every
  # confirmation loop.
  assert_source_contains "$file" 'if elapsed >= confirmationTimeoutSeconds then exit repeat' "bounded polling / $label"
  assert_source_contains "$file" 'property confirmationTimeoutSeconds' "documented timeout / $label"
  assert_source_contains "$file" 'property confirmationPollInterval' "documented poll interval / $label"

  # Exact-match comparison, never substring/contains matching, and
  # case-sensitive (namesMatch wraps its comparison in "considering
  # case" -- AppleScript string "is" is case-insensitive by default).
  assert_source_contains "$file" 'on namesMatch(actualValue, requestedValue)' "exact matcher present / $label"
  assert_source_contains "$file" 'considering case' "case-sensitive comparison / $label"
  assert_source_not_contains "$file" 'requestedValue contains' "no substring matching / $label"
  assert_source_not_contains "$file" 'actualValue contains' "no substring matching / $label"

  # trimWhitespace normalizes only whitespace -- never lowercases,
  # never strips punctuation, so it cannot make two distinct device
  # names collapse into a false match.
  assert_source_contains "$file" 'on trimWhitespace(s)' "whitespace-only normalization / $label"
  assert_source_not_contains "$file" 'lowercase' "no case folding / $label"

  # Timeout/unconfirmed paths raise a contextual error naming the device
  # -- never a quiet non-zero return with no message.
  assert_source_contains "$file" 'was not confirmed selected' "unconfirmed raises named error / $label"
done

# --- No handler treats a click as success without first reading back
# --- confirmed state: "on run argv" must call the *confirming* wrapper
# --- (confirmMenuSelection / selectDeviceFromCandidates), never the
# --- click-only helper (pickMenuItem), to populate camPicked/micPicked.
assert_source_contains "$ZOOM_SCPT" 'set camMenuResult to confirmMenuSelection(zoomProcessName, meetingMenuLabel, cameraMenuLabel, desiredCamera)' "on run argv uses confirming wrapper (Zoom camera)"
assert_source_contains "$ZOOM_SCPT" 'set micMenuResult to confirmMenuSelection(zoomProcessName, meetingMenuLabel, microphoneMenuLabel, desiredMic)' "on run argv uses confirming wrapper (Zoom microphone)"
assert_source_not_contains "$ZOOM_SCPT" 'set camMenuResult to pickMenuItem' "on run argv never uses the click-only helper directly (Zoom camera)"
assert_source_not_contains "$ZOOM_SCPT" 'set micMenuResult to pickMenuItem' "on run argv never uses the click-only helper directly (Zoom microphone)"

echo "PASS: [static] both confirmation results are tracked independently, both are required for success, polling is bounded and documented, matching is exact and case-sensitive with no substring/case-folding shortcuts, and 'on run argv' only ever records success via the confirming wrapper"

# ===========================================================================
# Section B: the 14 required confirmation scenarios, verified as targeted
# source assertions (no macOS/osascript runtime is available in this
# environment to exercise the handlers with synthetic System Events
# input -- the same constraint noted in every prior task's validation).
# ===========================================================================
echo
echo "== Static checks: the 14 required confirmation scenarios =="

# 1. Already-selected fast path -- Zoom menu route: reading the mark
#    before any click, and returning confirmed success without clicking.
assert_source_contains "$ZOOM_SCPT" 'set preCheck to readMenuItemMarkChar(procName, menuTitle, submenuTitle, itemName)' "1. already-selected fast path (Zoom menu)"
assert_source_contains "$ZOOM_SCPT" 'if item 1 of preCheck and markIndicatesSelected(item 2 of preCheck) then' "1. already-selected fast path (Zoom menu)"

# 2. Already-selected fast path -- pop-up/button controls (Zoom fallback
#    and Teams): reading the control's current value before any click.
assert_source_contains "$ZOOM_SCPT" 'set preCheck to readControlSelectionValue(procName, theControl)' "2. already-selected fast path (Zoom control)"
assert_source_contains "$TEAMS_SCPT" 'set preCheck to readControlSelectionValue(procName, theControl)' "2. already-selected fast path (Teams control)"
assert_source_contains "$ZOOM_SCPT" 'if item 1 of preCheck and namesMatch(item 2 of preCheck, deviceName) then' "2. already-selected fast path (Zoom control)"
assert_source_contains "$TEAMS_SCPT" 'if item 1 of preCheck and namesMatch(item 2 of preCheck, deviceName) then' "2. already-selected fast path (Teams control)"

# 3. Click changes state to an exact match -- the poll loop returns
#    {true, ""} only once namesMatch/markIndicatesSelected observes it.
assert_source_contains "$ZOOM_SCPT" 'if markIndicatesSelected(lastValue) then' "3. click-changes-to-exact-match (Zoom menu)"
assert_source_contains "$ZOOM_SCPT" 'if namesMatch(lastValue, deviceName) then' "3. click-changes-to-exact-match (Zoom control)"
assert_source_contains "$TEAMS_SCPT" 'if namesMatch(lastValue, deviceName) then' "3. click-changes-to-exact-match (Teams)"

# 4 & 8. Click succeeds but the resulting value never changes to match,
#    and the bounded confirmation window elapses -- a distinct, named
#    timeout diagnostic (not silently treated as success).
assert_source_contains "$ZOOM_SCPT" 'its mark/selected state never confirmed the change within' "4+8. click-value-unchanged / timeout (Zoom menu)"
assert_source_contains "$ZOOM_SCPT" 'its resulting value never matched within' "4+8. click-value-unchanged / timeout (Zoom control)"
assert_source_contains "$TEAMS_SCPT" 'its resulting value never matched within' "4+8. click-value-unchanged / timeout (Teams)"

# 5. Click changes the control to a different (wrong) device -- namesMatch
#    is exact equality, so a non-matching resulting value keeps polling /
#    times out rather than being accepted; covered by the same exact-match
#    contract asserted in Section A (namesMatch uses "is", not "contains").
assert_source_contains "$ZOOM_SCPT" 'return (trimWhitespace(actualValue) is (trimWhitespace(requestedValue)))' "5. click-changes-to-wrong-device (Zoom exact equality)"
assert_source_contains "$TEAMS_SCPT" 'return (trimWhitespace(actualValue) is (trimWhitespace(requestedValue)))' "5. click-changes-to-wrong-device (Teams exact equality)"

# 6. Requested item is absent entirely -- a distinct "unavailable" error,
#    not folded into the timeout/unreadable diagnostics.
assert_source_contains "$ZOOM_SCPT" 'unavailable on the matched control: ' "6. item-absent (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'unavailable on the matched control: ' "6. item-absent (Teams)"

# 7. Resulting value/state is unreadable -- a distinct diagnostic from a
#    genuine mismatch, and never assumed to match when unreadable.
assert_source_contains "$ZOOM_SCPT" 'could not be read to confirm the change' "7. value-unreadable (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'could not be read to confirm the change' "7. value-unreadable (Teams)"
assert_source_contains "$ZOOM_SCPT" 'on readControlSelectionValue(procName, control)' "7. value-unreadable read helper present (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'on readControlSelectionValue(procName, control)' "7. value-unreadable read helper present (Teams)"

# 9 & 10. Camera succeeds while microphone fails, and vice versa --
#    independent outcomes already asserted in Section A; re-confirmed
#    here as part of the explicit 14-scenario list via the aggregated
#    failure-message contract that names only the failed device.
assert_source_contains "$ZOOM_SCPT" 'set end of failureParts to "camera \"" & desiredCamera & "\" was not confirmed selected' "9. camera-succeeds-mic-fails / independent messages (Zoom)"
assert_source_contains "$ZOOM_SCPT" 'set end of failureParts to "microphone \"" & desiredMic & "\" was not confirmed selected' "10. mic-succeeds-camera-fails / independent messages (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'set end of failureParts to "camera \"" & desiredCamera & "\" was not confirmed selected' "9. camera-succeeds-mic-fails / independent messages (Teams)"
assert_source_contains "$TEAMS_SCPT" 'set end of failureParts to "microphone \"" & desiredMic & "\" was not confirmed selected' "10. mic-succeeds-camera-fails / independent messages (Teams)"

# 11. Both fail -- failureParts accumulates both messages into one error.
assert_source_contains "$ZOOM_SCPT" 'set failureParts to {}' "11. both-fail aggregation (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'set failureParts to {}' "11. both-fail aggregation (Teams)"

# 12. Both confirmed -- the script returns (success) as soon as both
#    tracking variables are true, without raising any error. Checked as
#    a two-line proximity match (the standalone "if camPicked and
#    micPicked then" guard immediately followed by a bare "return") since
#    grep -F cannot match a pattern spanning a newline.
for pair in "$ZOOM_SCPT:Zoom" "$TEAMS_SCPT:Teams"; do
  file="${pair%%:*}"
  label="${pair##*:}"
  if ! grep -A1 -E '^\s*if camPicked and micPicked then\s*$' "$file" | grep -q '^\s*return\s*$'; then
    fail "[12. both-confirmed early success ($label)] expected a standalone 'if camPicked and micPicked then' guard immediately followed by a bare 'return'"
  fi
done

# 13. Substring match must never count as confirmed -- namesMatch's own
#    equality check is asserted in Section A; here we additionally assert
#    that neither selector ever calls namesMatch/markIndicatesSelected
#    results as "contains"-based, i.e. there is no alternate substring
#    based confirmation path anywhere in either file.
if grep -qE 'contains[^"]*deviceName' "$ZOOM_SCPT"; then
  fail "[13. substring-must-not-match] found a 'contains ... deviceName' style comparison in $(basename "$ZOOM_SCPT") -- confirmation must use exact equality only"
fi
if grep -qE 'contains[^"]*deviceName' "$TEAMS_SCPT"; then
  fail "[13. substring-must-not-match] found a 'contains ... deviceName' style comparison in $(basename "$TEAMS_SCPT") -- confirmation must use exact equality only"
fi

# 14. Unicode/punctuation-exact-match -- trimWhitespace's character set is
#    exactly space/tab/return/linefeed (never touching other Unicode
#    characters or punctuation), and the comparison is wrapped in
#    "considering case" so it is genuinely case-sensitive, not just
#    "looks case-sensitive".
assert_source_contains "$ZOOM_SCPT" 'character startIdx of s is " " or character startIdx of s is tab or character startIdx of s is return or character startIdx of s is linefeed' "14. Unicode/punctuation-exact-match (Zoom trim char set)"
assert_source_contains "$TEAMS_SCPT" 'character startIdx of s is " " or character startIdx of s is tab or character startIdx of s is return or character startIdx of s is linefeed' "14. Unicode/punctuation-exact-match (Teams trim char set)"

echo "PASS: [contract] all 14 required confirmation scenarios have a corresponding, verifiable code path"

# ===========================================================================
# Section C: osacompile validation (syntax only; never executed).
# ===========================================================================
echo
echo "== osacompile validation =="
if command -v osacompile >/dev/null 2>&1; then
  compile_dir="$(mktemp -d)"
  if osacompile -o "$compile_dir/select_zoom_camera.scpt.compiled" "$ZOOM_SCPT" 2>"$compile_dir/zoom_err.log"; then
    echo "PASS: [osacompile] scripts/select_zoom_camera.scpt compiles"
  else
    fail "[osacompile] scripts/select_zoom_camera.scpt failed to compile: $(cat "$compile_dir/zoom_err.log")"
  fi
  if osacompile -o "$compile_dir/select_teams_camera.scpt.compiled" "$TEAMS_SCPT" 2>"$compile_dir/teams_err.log"; then
    echo "PASS: [osacompile] scripts/select_teams_camera.scpt compiles"
  else
    fail "[osacompile] scripts/select_teams_camera.scpt failed to compile: $(cat "$compile_dir/teams_err.log")"
  fi
  rm -rf "$compile_dir"
else
  echo "SKIP: [osacompile] not available in this environment -- all other validation still ran"
fi

# ===========================================================================
# Section D: shell-launcher propagation -- both an unconfirmed-selection
# failure and a confirmed-success case, for both launchers. Mocks open/
# pgrep/sleep to simulate a fast, successful app launch; osascript is
# mocked separately per scenario. No real Zoom, Teams, or System Events
# automation is invoked.
# ===========================================================================
echo
echo "== Shell propagation: unconfirmed selection and confirmed success =="

write_mock open '
exit 0
'
write_mock pgrep '
exit 0
'
write_mock sleep '
exit 0
'

run_launcher() {
  local script_rel="$1" invocations_file="$2" out_file="$3" err_file="$4"
  local script_path="$repo_root/$script_rel"
  set +e
  OSASCRIPT_INVOCATIONS_FILE="$invocations_file" \
    PATH="$mock_dir:$PATH" OSASCRIPT_BIN="$mock_dir/osascript" \
    LAUNCHER_ATTEMPTS=3 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    bash "$script_path" > "$out_file" 2> "$err_file"
  echo $?
}

test_unconfirmed_selection_propagates() {
  local launcher_name="$1" script_rel="$2"
  local scenario_dir invocations_file out_file err_file status

  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_unconfirmed"
  mkdir -p "$scenario_dir"
  invocations_file="$scenario_dir/osascript_invocations.log"
  : > "$invocations_file"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  write_mock osascript '
if [[ -n "${OSASCRIPT_INVOCATIONS_FILE:-}" ]]; then
  echo "invoked" >> "$OSASCRIPT_INVOCATIONS_FILE"
fi
echo "osascript: device selection failed: camera \"iPhone Camera\" was not confirmed selected (clicked \"iPhone Camera\" on the matched control but its resulting value never matched within 3.0s (last observed: \"Built-in Camera\"))" >&2
exit 1
'

  status="$(run_launcher "$script_rel" "$invocations_file" "$out_file" "$err_file")"
  out_content="$(cat "$out_file")"
  err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ "$status" -eq 0 ]]; then
    fail "[$launcher_name / unconfirmed] expected a nonzero exit status when the selection cannot be confirmed, got 0"
  fi
  if ! echo "$err_content" | grep -q "was not confirmed selected"; then
    fail "[$launcher_name / unconfirmed] expected the unconfirmed-selection diagnostic to remain visible on stderr, got: $err_content"
  fi
  local invocation_count
  invocation_count="$(wc -l < "$invocations_file" | tr -d ' ')"
  if [[ "$invocation_count" != "1" ]]; then
    fail "[$launcher_name / unconfirmed] expected osascript to be invoked exactly once, got $invocation_count"
  fi
  if [[ -n "$out_content" ]]; then
    fail "[$launcher_name / unconfirmed] expected no stdout success output after an unconfirmed selection, got: $out_content"
  fi

  echo "PASS: [$launcher_name] an unconfirmed selection exits the launcher nonzero and keeps the confirmation diagnostic visible"
}

test_confirmed_success_propagates() {
  local launcher_name="$1" script_rel="$2"
  local scenario_dir invocations_file out_file err_file status

  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_confirmed"
  mkdir -p "$scenario_dir"
  invocations_file="$scenario_dir/osascript_invocations.log"
  : > "$invocations_file"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  # A real successful run's "on run argv" falls off the end after both
  # camPicked and micPicked are true, raising no error and printing
  # nothing -- so a faithful mock exits 0 with empty stdout/stderr.
  write_mock osascript '
if [[ -n "${OSASCRIPT_INVOCATIONS_FILE:-}" ]]; then
  echo "invoked" >> "$OSASCRIPT_INVOCATIONS_FILE"
fi
exit 0
'

  status="$(run_launcher "$script_rel" "$invocations_file" "$out_file" "$err_file")"
  out_content="$(cat "$out_file")"
  err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ "$status" -ne 0 ]]; then
    fail "[$launcher_name / confirmed-success] expected a zero exit status once both devices are confirmed selected, got $status"
  fi
  if [[ -n "$err_content" ]]; then
    fail "[$launcher_name / confirmed-success] expected no stderr diagnostic on a confirmed success, got: $err_content"
  fi
  local invocation_count
  invocation_count="$(wc -l < "$invocations_file" | tr -d ' ')"
  if [[ "$invocation_count" != "1" ]]; then
    fail "[$launcher_name / confirmed-success] expected osascript to be invoked exactly once, got $invocation_count"
  fi

  echo "PASS: [$launcher_name] a confirmed selection exits the launcher zero with no error output"
}

test_unconfirmed_selection_propagates "Zoom" "scripts/start_zoom.sh"
test_unconfirmed_selection_propagates "Microsoft Teams" "scripts/start_teams.sh"
test_confirmed_success_propagates "Zoom" "scripts/start_zoom.sh"
test_confirmed_success_propagates "Microsoft Teams" "scripts/start_teams.sh"

echo
echo "All device-selection confirmation regression checks passed."

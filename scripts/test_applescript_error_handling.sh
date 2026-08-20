#!/usr/bin/env bash
# Regression coverage for the AppleScript error-handling hardening fix:
# every try/on-error block in the Zoom and Teams selectors must either
# (a) deliberately attempt another supported strategy, (b) be a genuinely
# optional/harmless lookup, or (c) record a diagnostic, return an explicit
# failure result, or raise a final error -- never silently discard a
# caught error. This file never launches real Zoom, Teams, or System
# Events automation; it only performs static source assertions, an
# osacompile syntax check (if available), and mock-based shell-launcher
# propagation checks.
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

# ===========================================================================
# Section A: static source assertions -- no silently discarded errors.
#
# These are targeted, per-known-operation assertions (not a generic
# AppleScript parser), matching the specific handlers this fix touches, so
# ordinary formatting changes elsewhere in the file do not cause false
# failures.
# ===========================================================================
echo "== Static checks: no silently discarded AppleScript errors =="

for pair in "$ZOOM_SCPT:Zoom" "$TEAMS_SCPT:Teams"; do
  file="${pair%%:*}"
  label="${pair##*:}"

  # --- No bare boolean-only success/failure results remain anywhere. ---
  # Every helper in both files used to return a bare `true`/`false` from
  # at least one caught-error path, discarding the underlying AppleScript
  # error entirely. All of them now return a {success, diagnostic} pair
  # instead, so no "return true" / "return false" statement should exist
  # anywhere in either production selector.
  if grep -qE '(^|[^"a-zA-Z])return true([^"a-zA-Z]|$)' "$file"; then
    fail "[static / $label] found a bare 'return true' -- results must be a {success, diagnostic} pair, not a bare Boolean"
  fi
  if grep -qE '(^|[^"a-zA-Z])return false([^"a-zA-Z]|$)' "$file"; then
    fail "[static / $label] found a bare 'return false' -- a caught error must be recorded as a {false, diagnostic} pair, never a bare Boolean"
  fi

  # --- Every remaining "on error" clause captures both a message and a
  # --- number (the task's explicit "capture message and number" rule),
  # --- and is never a truly bare/empty "on error" with no variable.
  while IFS= read -r on_error_line; do
    case "$on_error_line" in
      *"on error"*"number"*) : ;;
      *)
        fail "[static / $label] found an 'on error' clause that does not capture both a message and an error number: $on_error_line"
        ;;
    esac
  done < <(grep -E 'on error' "$file")

  # --- Every caught error variable is actually used (not declared and
  # --- ignored). For each "on error <var> number <var2>" line, the two
  # --- variable names must appear again within the next few lines (the
  # --- handler's own return/diagnostic-building statement), which is a
  # --- deliberately narrow, line-proximity check rather than a full
  # --- control-flow parse.
  while IFS=: read -r line_no on_error_line; do
    var1="$(echo "$on_error_line" | sed -E 's/.*on error ([A-Za-z_][A-Za-z0-9_]*) number ([A-Za-z_][A-Za-z0-9_]*).*/\1/')"
    var2="$(echo "$on_error_line" | sed -E 's/.*on error ([A-Za-z_][A-Za-z0-9_]*) number ([A-Za-z_][A-Za-z0-9_]*).*/\2/')"
    # A window of 8 lines is wide enough to reach the eventual usage even
    # when a nested try/on-error sits between the catch and the statement
    # that uses the captured variable (as in Teams' activateCandidate,
    # whose outer clickErrMsg/clickErrNum are only referenced once the
    # inner AXPress fallback also fails), while still being narrow enough
    # that an unrelated later reuse of the same short variable name
    # elsewhere in the file cannot produce a false pass.
    window="$(sed -n "$((line_no+1)),$((line_no+8))p" "$file")"
    if ! echo "$window" | grep -q "$var1"; then
      fail "[static / $label] captured error-message variable '$var1' (declared at line $line_no) is never used"
    fi
    if ! echo "$window" | grep -q "$var2"; then
      fail "[static / $label] captured error-number variable '$var2' (declared at line $line_no) is never used"
    fi
  done < <(grep -nE 'on error [A-Za-z_]+ number [A-Za-z_]+' "$file")

  # --- Both device outcomes are checked before the selector can return
  # --- success -- the exact guard that makes partial success impossible.
  if ! grep -q 'camPicked and micPicked' "$file"; then
    fail "[static / $label] expected an explicit 'camPicked and micPicked' check before reporting success"
  fi

  # --- A final, contextual error is raised when the necessary selection
  # --- cannot be completed (never a quiet non-zero return with no
  # --- message, and never continuing past this point silently).
  if ! grep -qE 'error "(Zoom|Teams) device selection failed: " & failureText' "$file"; then
    fail "[static / $label] expected a single final contextual error naming the failed device(s) when selection cannot be completed"
  fi

  # --- The application-not-running guard raises directly (no try/catch
  # --- swallowing this required check).
  if ! grep -qE 'error "(Zoom|Teams) is not running' "$file"; then
    fail "[static / $label] expected a direct application-not-running error"
  fi
done

# --- Zoom: the menu-route helper's failure feeds the *real* diagnostic,
# --- not a generic placeholder, into camDiagnostic/micDiagnostic.
if ! grep -q 'set camDiagnostic to item 2 of camMenuResult' "$ZOOM_SCPT"; then
  fail "[static / Zoom] expected the menu route's captured diagnostic to seed camDiagnostic on failure"
fi
if ! grep -q 'set micDiagnostic to item 2 of micMenuResult' "$ZOOM_SCPT"; then
  fail "[static / Zoom] expected the menu route's captured diagnostic to seed micDiagnostic on failure"
fi

# --- Teams: Settings-open failure aggregates both the menu strategy's and
# --- the Command-, shortcut's captured diagnostics (never just the
# --- shortcut's, and never a generic message with no underlying detail).
if ! grep -q 'set settingsDiagnostic to item 2 of menuResult' "$TEAMS_SCPT"; then
  fail "[static / Teams] expected the Settings-menu strategy's captured diagnostic to be recorded before the shortcut fallback runs"
fi
if ! grep -q 'set settingsDiagnostic to settingsDiagnostic & "; " & (item 2 of shortcutResult)' "$TEAMS_SCPT"; then
  fail "[static / Teams] expected the Command-, shortcut's captured diagnostic to be appended, not to replace, the menu strategy's diagnostic"
fi
if ! grep -q 'error "Teams settings could not be opened (" & settingsDiagnostic & ")."' "$TEAMS_SCPT"; then
  fail "[static / Teams] expected the Settings-open failure to raise both captured strategy diagnostics"
fi

# --- Teams: the Devices-activation failure records activateCandidate's
# --- real diagnostic (click + AXPress details), not a generic message.
if ! grep -q 'set devicesDiagnostic to "found a control matching \\"" & devicesLabel & "\\" but could not activate it: " & (item 2 of activateResult)' "$TEAMS_SCPT"; then
  fail "[static / Teams] expected the Devices-activation failure to include activateCandidate's captured diagnostic"
fi

# --- Ambiguous-match failures are explicit, not a silent first-match
# --- guess, in both selectors' device-control lookup and (Teams-only)
# --- the Devices navigation lookup.
if ! grep -q 'ambiguous match: " & (count of candidates) & " controls matched' "$ZOOM_SCPT"; then
  fail "[static / Zoom] expected an explicit ambiguous-match failure in selectDeviceFromCandidates"
fi
if ! grep -q 'ambiguous match: " & (count of candidates) & " controls matched' "$TEAMS_SCPT"; then
  fail "[static / Teams] expected an explicit ambiguous-match failure in selectDeviceFromCandidates"
fi
if ! grep -q 'ambiguous match: " & (count of navCandidates) & " controls matched' "$TEAMS_SCPT"; then
  fail "[static / Teams] expected an explicit ambiguous-match failure when locating the Devices entry point"
fi

# --- No eval / no arbitrary coordinate clicks / no third-party deps.
for file in "$ZOOM_SCPT" "$TEAMS_SCPT"; do
  if grep -qiE '\bclick at\b' "$file"; then
    fail "[static / $(basename "$file")] found an arbitrary coordinate click ('click at')"
  fi
done

echo "PASS: [static] no bare Boolean results, every 'on error' captures a message and a number, every captured variable is used, both device outcomes are required, and every required failure raises a contextual final error"

# ===========================================================================
# Section B: behavioral-contract coverage via targeted source assertions.
#
# There is no macOS/osascript runtime available in this environment (see
# every prior task's validation notes), so the eight success/failure
# scenarios below cannot be exercised by actually running the AppleScript
# handlers with synthetic System Events input. Each is instead verified by
# confirming the specific code path that implements it is present, which
# is the "targeted assertions" approach the task calls for rather than a
# large fake accessibility framework.
# ===========================================================================
echo
echo "== Static checks: behavioral-contract code paths =="

assert_source_contains() {
  local file="$1" pattern="$2" scenario="$3"
  if ! grep -qF "$pattern" "$file"; then
    fail "[contract / $scenario] expected pattern not found in $(basename "$file"): $pattern"
  fi
}

# 1. Both camera and microphone succeed -> the only two-sided success gate.
assert_source_contains "$ZOOM_SCPT" 'if camPicked and micPicked then' "both succeed (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'if camPicked and micPicked then' "both succeed (Teams)"

# 2. Preferred strategy fails but fallback succeeds -> Strategy 2 only runs
#    for whichever device Strategy 1 (menu route) did not already confirm.
assert_source_contains "$ZOOM_SCPT" 'if not camPicked or not micPicked then' "preferred fails, fallback succeeds (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'if not settingsOpened then' "preferred fails, fallback succeeds (Teams settings)"

# 3 & 4. Camera succeeds / microphone fails, and vice versa -> independent
#    tracking variables, each with its own diagnostic.
assert_source_contains "$ZOOM_SCPT" 'set camPicked to false' "independent camera tracking (Zoom)"
assert_source_contains "$ZOOM_SCPT" 'set micPicked to false' "independent microphone tracking (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'set camPicked to false' "independent camera tracking (Teams)"
assert_source_contains "$TEAMS_SCPT" 'set micPicked to false' "independent microphone tracking (Teams)"

# 5. Both fail -> failureParts accumulates both, joined into one message.
assert_source_contains "$ZOOM_SCPT" 'set failureParts to {}' "both fail, aggregated diagnostic (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'set failureParts to {}' "both fail, aggregated diagnostic (Teams)"

# 6. Application not running -> direct error before any UI scripting.
assert_source_contains "$ZOOM_SCPT" 'error "Zoom is not running (process \"" & zoomProcessName & "\" not found)."' "application not running (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'error "Teams is not running (process \"" & appName & "\" not found)."' "application not running (Teams)"

# 7. Ambiguous control match -> explicit failure, never an unpredictable
#    first-match guess (already asserted above; re-confirmed here as part
#    of the explicit scenario list).
assert_source_contains "$ZOOM_SCPT" 'return {false, "ambiguous match: "' "ambiguous match (Zoom)"
assert_source_contains "$TEAMS_SCPT" 'return {false, "ambiguous match: "' "ambiguous match (Teams)"

# 8. Multiple failed strategies contribute details to the final error ->
#    Zoom's Strategy-2 fallback appends onto Strategy-1's diagnostic
#    instead of replacing it; Teams' Settings stage appends the shortcut's
#    diagnostic onto the menu strategy's diagnostic.
assert_source_contains "$ZOOM_SCPT" '"; fallback: " & (item 2 of camResult)' "multiple strategies aggregated (Zoom camera)"
assert_source_contains "$ZOOM_SCPT" '"; fallback: " & (item 2 of micResult)' "multiple strategies aggregated (Zoom microphone)"
assert_source_contains "$TEAMS_SCPT" 'set settingsDiagnostic to settingsDiagnostic & "; " & (item 2 of shortcutResult)' "multiple strategies aggregated (Teams settings)"

echo "PASS: [contract] all eight success/failure scenarios have a corresponding, verifiable code path"

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
# Section D: shell-launcher propagation of a selector failure.
#
# Mocks open/pgrep to simulate a successful, fast launch, then mocks
# osascript to print a contextual selector error to stderr and exit
# nonzero (exactly what a raised AppleScript "error" statement produces).
# No real Zoom, Teams, or System Events automation is invoked.
# ===========================================================================
echo
echo "== Shell propagation: selector failure exits the launcher nonzero =="

write_mock open '
exit 0
'
write_mock pgrep '
# Exact-match mock: succeeds immediately so the launcher reaches the
# selector step without consuming the full attempt budget.
exit 0
'
write_mock sleep '
exit 0
'
write_mock osascript '
if [[ -n "${OSASCRIPT_INVOCATIONS_FILE:-}" ]]; then
  echo "invoked" >> "$OSASCRIPT_INVOCATIONS_FILE"
fi
echo "osascript: device selection failed: camera \"iPhone Camera\" was not selected (menu route (Meeting > Select Camera > iPhone Camera) failed: Can'"'"'t get menu \"Select Camera\". (error -1728))" >&2
exit 1
'

test_selector_failure_propagates() {
  local launcher_name="$1" script_rel="$2"
  local script_path="$repo_root/$script_rel"
  local scenario_dir invocations_file out_file err_file status

  scenario_dir="$mock_dir/$(echo "$launcher_name" | tr ' ' '_')_selector_failure"
  mkdir -p "$scenario_dir"
  invocations_file="$scenario_dir/osascript_invocations.log"
  : > "$invocations_file"
  out_file="$scenario_dir/stdout.log"
  err_file="$scenario_dir/stderr.log"

  set +e
  OSASCRIPT_INVOCATIONS_FILE="$invocations_file" \
    PATH="$mock_dir:$PATH" OSASCRIPT_BIN="$mock_dir/osascript" \
    LAUNCHER_ATTEMPTS=3 LAUNCHER_POLL_INTERVAL=0 LAUNCHER_SETTLE_DELAY=0 \
    bash "$script_path" > "$out_file" 2> "$err_file"
  status=$?
  set -e

  out_content="$(cat "$out_file")"
  err_content="$(cat "$err_file")"
  echo "stdout: $out_content"
  echo "stderr: $err_content"

  if [[ $status -eq 0 ]]; then
    fail "[$launcher_name / selector-failure] expected a nonzero exit status when the selector raises an error, got 0"
  fi

  if ! echo "$err_content" | grep -q "device selection failed: camera"; then
    fail "[$launcher_name / selector-failure] expected the selector's contextual AppleScript error text to remain visible on stderr, got: $err_content"
  fi

  local invocation_count
  invocation_count="$(wc -l < "$invocations_file" | tr -d ' ')"
  if [[ "$invocation_count" != "1" ]]; then
    fail "[$launcher_name / selector-failure] expected osascript to be invoked exactly once, got $invocation_count"
  fi

  if [[ -n "$out_content" ]]; then
    fail "[$launcher_name / selector-failure] expected no stdout output after a selector failure (no success message), got: $out_content"
  fi

  echo "PASS: [$launcher_name] a selector failure exits the launcher nonzero, keeps the AppleScript diagnostic visible, invokes osascript exactly once, and prints no success output"
}

test_selector_failure_propagates "Zoom" "scripts/start_zoom.sh"
test_selector_failure_propagates "Microsoft Teams" "scripts/start_teams.sh"

echo
echo "All AppleScript error-handling regression checks passed."

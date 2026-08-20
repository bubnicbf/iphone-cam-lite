#!/usr/bin/env bash
# Regression test for the ZOOM_*/TEAMS_* UI-label configuration added to
# scripts/start_zoom.sh, scripts/start_teams.sh, and their AppleScript
# selectors.
#
# This covers argument-passing correctness only (default labels,
# localized/Unicode labels, independent per-variable overrides, empty
# values falling back to defaults, and no leakage between the Zoom-only
# and Teams-only variables). It reuses the same isolated-mock-directory
# approach as scripts/test_launcher_failures.sh (never touching real
# system state, never launching real Zoom, Teams, or System Events
# automation) but keeps its own small, self-contained mock set since its
# scenarios only need `open`/`pgrep`/`sleep` to succeed quickly and are
# entirely about what reaches `osascript`, not about launch timing itself.

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

write_mock open '
exit 0
'

# pgrep: always reports the process present on the first check, so every
# scenario here reaches the osascript call quickly regardless of which
# launcher is under test.
write_mock pgrep '
exit 0
'

write_mock sleep '
exit 0
'

# osascript: records the real argument COUNT and each argument on its own
# line (not space-joined), so a quoting/splitting bug cannot hide inside a
# single merged string, and always exits 0 (these tests are only about
# what reaches osascript, not about selector success/failure).
write_mock osascript '
echo "$#" >> "${ARGC_FILE:?}"
printf "%s\n" "$@" > "${ARGS_FILE:?}"
exit 0
'

# run_and_capture invokes a launcher with the given environment already
# exported by the caller, capturing osascript'"'"'s argument count/values.
# Does not manage set -e itself -- callers wrap with set +e/set -e.
run_and_capture() {
  local script_path="$1" argc_file="$2" args_file="$3" out_file="$4" err_file="$5"
  PATH="$mock_dir:$PATH" OSASCRIPT_BIN="$mock_dir/osascript" \
    ARGC_FILE="$argc_file" ARGS_FILE="$args_file" \
    bash "$script_path" > "$out_file" 2> "$err_file"
}

new_scenario_dir() {
  mktemp -d "$mock_dir/scenario.XXXXXX"
}

# assert_args compares the captured argument list (one per line) against
# the expected pipe-separated sequence, failing with full context if they
# differ in count, order, or exact content at any position.
assert_args() {
  local label="$1" args_file="$2" expected="$3"
  local actual
  actual="$(cat "$args_file" 2>/dev/null | tr '\n' '|')"
  actual="${actual%|}"
  if [[ "$actual" != "$expected" ]]; then
    fail "[$label] expected osascript arguments:
  $expected
got:
  $actual"
  fi
}

echo "== Scenario: Zoom, default labels (no overrides) =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
run_and_capture "$repo_root/scripts/start_zoom.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[zoom-default] expected exit 0, got $status (stderr: $(cat "$err_file"))"
[[ "$(cat "$argc_file")" == "8" ]] || fail "[zoom-default] expected argc 8, got $(cat "$argc_file")"
expected="$repo_root/scripts/select_zoom_camera.scpt|iPhone Camera|iPhone Microphone|Meeting|Select Camera|Select Microphone|Select a camera|Select a microphone"
assert_args "zoom-default" "$args_file" "$expected"
echo "PASS: Zoom default labels passed in the documented order"

echo
echo "== Scenario: Teams, default labels (no overrides) =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
run_and_capture "$repo_root/scripts/start_teams.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[teams-default] expected exit 0, got $status (stderr: $(cat "$err_file"))"
[[ "$(cat "$argc_file")" == "7" ]] || fail "[teams-default] expected argc 7, got $(cat "$argc_file")"
expected="$repo_root/scripts/select_teams_camera.scpt|iPhone Camera|iPhone Microphone|Settings|Devices|Camera|Microphone"
assert_args "teams-default" "$args_file" "$expected"
echo "PASS: Teams default labels passed in the documented order"

echo
echo "== Scenario: Zoom, every label localized (Unicode) =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
CAMERA_NAME="Cámara de Benjamín" MICROPHONE_NAME="Micrófono (Estudio)" \
  ZOOM_MEETING_MENU_LABEL="Réunion" ZOOM_CAMERA_MENU_LABEL="Sélectionner la caméra" \
  ZOOM_MICROPHONE_MENU_LABEL="Sélectionner le microphone" \
  ZOOM_CAMERA_CONTROL_LABEL="选择摄像头" ZOOM_MICROPHONE_CONTROL_LABEL="选择麦克风 (桌面)" \
  run_and_capture "$repo_root/scripts/start_zoom.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[zoom-localized] expected exit 0, got $status (stderr: $(cat "$err_file"))"
[[ "$(cat "$argc_file")" == "8" ]] || fail "[zoom-localized] expected argc 8, got $(cat "$argc_file")"
expected="$repo_root/scripts/select_zoom_camera.scpt|Cámara de Benjamín|Micrófono (Estudio)|Réunion|Sélectionner la caméra|Sélectionner le microphone|选择摄像头|选择麦克风 (桌面)"
assert_args "zoom-localized" "$args_file" "$expected"
echo "PASS: Zoom localized Unicode labels passed exactly, none split/truncated/replaced by defaults"

echo
echo "== Scenario: Teams, every label localized (Unicode), and Zoom-only vars must not leak =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
ZOOM_MEETING_MENU_LABEL="SHOULD NOT APPEAR IN TEAMS ARGS" \
  TEAMS_SETTINGS_MENU_LABEL="Einstellungen" TEAMS_DEVICES_LABEL="Geräte" \
  TEAMS_CAMERA_CONTROL_LABEL="Kamera" TEAMS_MICROPHONE_CONTROL_LABEL="Mikrofon (Büro)" \
  run_and_capture "$repo_root/scripts/start_teams.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[teams-localized] expected exit 0, got $status (stderr: $(cat "$err_file"))"
[[ "$(cat "$argc_file")" == "7" ]] || fail "[teams-localized] expected argc 7, got $(cat "$argc_file")"
expected="$repo_root/scripts/select_teams_camera.scpt|iPhone Camera|iPhone Microphone|Einstellungen|Geräte|Kamera|Mikrofon (Büro)"
assert_args "teams-localized" "$args_file" "$expected"
if grep -q "SHOULD NOT APPEAR" "$args_file"; then
  fail "[teams-localized] a Zoom-only variable (ZOOM_MEETING_MENU_LABEL) leaked into the Teams selector's arguments"
fi
echo "PASS: Teams localized Unicode labels passed exactly, and the Zoom-only variable did not leak in"

echo
echo "== Scenario: Zoom, independent override (only ZOOM_CAMERA_MENU_LABEL set) =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
ZOOM_CAMERA_MENU_LABEL="Câmera" \
  run_and_capture "$repo_root/scripts/start_zoom.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[zoom-independent] expected exit 0, got $status"
expected="$repo_root/scripts/select_zoom_camera.scpt|iPhone Camera|iPhone Microphone|Meeting|Câmera|Select Microphone|Select a camera|Select a microphone"
assert_args "zoom-independent" "$args_file" "$expected"
echo "PASS: overriding only ZOOM_CAMERA_MENU_LABEL leaves every other Zoom label at its default"

echo
echo "== Scenario: Teams, independent override (only TEAMS_DEVICES_LABEL set) =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
TEAMS_DEVICES_LABEL="Périphériques" \
  run_and_capture "$repo_root/scripts/start_teams.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[teams-independent] expected exit 0, got $status"
expected="$repo_root/scripts/select_teams_camera.scpt|iPhone Camera|iPhone Microphone|Settings|Périphériques|Camera|Microphone"
assert_args "teams-independent" "$args_file" "$expected"
echo "PASS: overriding only TEAMS_DEVICES_LABEL leaves every other Teams label at its default"

echo
echo "== Scenario: Zoom, empty-string overrides fall back to defaults =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
ZOOM_MEETING_MENU_LABEL="" ZOOM_CAMERA_MENU_LABEL="" ZOOM_MICROPHONE_MENU_LABEL="" \
  ZOOM_CAMERA_CONTROL_LABEL="" ZOOM_MICROPHONE_CONTROL_LABEL="" \
  run_and_capture "$repo_root/scripts/start_zoom.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[zoom-empty] expected exit 0, got $status"
expected="$repo_root/scripts/select_zoom_camera.scpt|iPhone Camera|iPhone Microphone|Meeting|Select Camera|Select Microphone|Select a camera|Select a microphone"
assert_args "zoom-empty" "$args_file" "$expected"
echo "PASS: empty-string Zoom label overrides fall back to their documented English defaults"

echo
echo "== Scenario: Teams, empty-string overrides fall back to defaults =="
dir="$(new_scenario_dir)"
argc_file="$dir/argc"; args_file="$dir/args"; out_file="$dir/out"; err_file="$dir/err"
set +e
TEAMS_SETTINGS_MENU_LABEL="" TEAMS_DEVICES_LABEL="" TEAMS_CAMERA_CONTROL_LABEL="" TEAMS_MICROPHONE_CONTROL_LABEL="" \
  run_and_capture "$repo_root/scripts/start_teams.sh" "$argc_file" "$args_file" "$out_file" "$err_file"
status=$?
set -e
[[ $status -eq 0 ]] || fail "[teams-empty] expected exit 0, got $status"
expected="$repo_root/scripts/select_teams_camera.scpt|iPhone Camera|iPhone Microphone|Settings|Devices|Camera|Microphone"
assert_args "teams-empty" "$args_file" "$expected"
echo "PASS: empty-string Teams label overrides fall back to their documented English defaults"

# --- Source-level regression assertions ----------------------------------
echo
echo "== Static checks: selector source hardening =="

for selector_script in "scripts/select_zoom_camera.scpt" "scripts/select_teams_camera.scpt"; do
  selector_path="$repo_root/$selector_script"

  if ! grep -q '^on run argv' "$selector_path"; then
    fail "[static / $selector_script] expected an explicit run handler accepting arguments (on run argv)"
  fi

  if ! grep -q 'resolveArg(argv' "$selector_path"; then
    fail "[static / $selector_script] expected the selector to read its UI-label arguments via a documented resolver"
  fi

  # The old English labels must remain the *defaults*, not the only
  # accepted values -- i.e. they appear as property initializers, and the
  # handler also reads overrides from argv (checked above).
  if ! grep -qE '^property (desiredCamera|desiredMic) :' "$selector_path"; then
    fail "[static / $selector_script] expected desiredCamera/desiredMic default properties to remain"
  fi

  # Must no longer rely exclusively on "window 1" -- some bounded,
  # multi-window search helper must exist.
  if ! grep -q 'relevantWindows' "$selector_path"; then
    fail "[static / $selector_script] expected a bounded multi-window search helper (relevantWindows), not exclusive window 1 access"
  fi
  if grep -qE 'of window 1[^0-9]' "$selector_path"; then
    fail "[static / $selector_script] still references \"window 1\" directly in production logic"
  fi

  # Camera/microphone outcomes must be tracked independently, and success
  # must require both.
  if ! grep -q 'camPicked' "$selector_path" || ! grep -q 'micPicked' "$selector_path"; then
    fail "[static / $selector_script] expected camera and microphone success to be tracked with independent variables"
  fi
  if ! grep -q 'camPicked and micPicked' "$selector_path"; then
    fail "[static / $selector_script] expected selector completion to require both camPicked and micPicked"
  fi

  # Failures must be raised (error ...), not swallowed by an empty
  # on-error handler.
  if ! grep -q '^  error "' "$selector_path"; then
    fail "[static / $selector_script] expected the selector to raise a final actionable error on failure"
  fi
done

echo "PASS: both selectors have an argv-accepting run handler, resolve UI labels with documented defaults, search bounded multiple windows instead of only window 1, track camera/microphone success independently, require both to succeed, and raise an actionable error on failure"

echo
echo "All UI-label configuration regression checks passed."

#!/usr/bin/env bash
# Safety regression test for scripts/reset_camera_services.sh.
#
# That script restarts camera-related system agents and kills a specific
# helper process by name -- both are real system-changing operations, so
# this test never lets the real launchctl/pkill run. It mocks both,
# recording every invocation, and asserts: (a) the script only targets the
# specific, documented services/process pattern (never a broad wildcard or
# unrelated target), (b) a failing launchctl/pkill does not abort the
# script (each is guarded with "|| true"), and (c) the script contains no
# other destructive command (rm -rf, sudo, shutdown, reboot, diskutil...).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="$repo_root/scripts/reset_camera_services.sh"

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

if [[ ! -f "$script_path" ]]; then
  fail "scripts/reset_camera_services.sh not found"
fi

echo "== Static checks: only the documented, specific targets are used =="

if ! grep -q '^set -euo pipefail$' "$script_path"; then
  fail "reset_camera_services.sh does not enable 'set -euo pipefail'"
fi

# Every external command that changes system state must be guarded with
# "|| true" so a single missing/failing agent never aborts the rest of the
# reset, and never propagates a nonzero exit for something this script
# cannot control (like a service that's already stopped).
for pattern in 'launchctl kickstart' 'pkill -f'; do
  line="$(grep -F "$pattern" "$script_path" || true)"
  if [[ -z "$line" ]]; then
    fail "expected a '$pattern' invocation in reset_camera_services.sh"
  fi
  if ! echo "$line" | grep -q '|| true'; then
    fail "expected '$pattern' to be guarded with '|| true' so a failure doesn't abort the script: $line"
  fi
done

# No unrelated destructive command should ever be introduced here.
for dangerous in 'rm -rf' 'sudo ' 'shutdown' 'reboot' 'diskutil' 'dd if=' 'mkfs'; do
  if grep -qF "$dangerous" "$script_path"; then
    fail "found an unexpected destructive command ('$dangerous') in reset_camera_services.sh"
  fi
done
echo "PASS: [static] set -euo pipefail is enabled, launchctl/pkill are guarded with '|| true', and no unrelated destructive command is present"

# pkill must target a specific, named pattern -- never an empty or
# wildcard-only pattern that could match unrelated processes.
pkill_pattern="$(grep -oE 'pkill -f "[^"]*"' "$script_path" | head -1 | sed -E 's/pkill -f "(.*)"/\1/')"
if [[ -z "$pkill_pattern" ]]; then
  fail "pkill -f pattern is empty or could not be parsed from reset_camera_services.sh -- an empty pattern could match unrelated processes"
fi
echo "PASS: [static] pkill targets a specific non-empty pattern (\"$pkill_pattern\"), not an unbounded match"

echo
echo "== Mocked execution: launchctl/pkill are invoked, never run for real =="

invocations_file="$mock_dir/invocations.log"
: > "$invocations_file"

write_mock launchctl "
echo \"launchctl \$*\" >> '$invocations_file'
exit 0
"
write_mock pkill "
echo \"pkill \$*\" >> '$invocations_file'
exit 0
"

out_file="$mock_dir/stdout.log"
err_file="$mock_dir/stderr.log"
set +e
PATH="$mock_dir:$PATH" bash "$script_path" > "$out_file" 2> "$err_file"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  fail "reset_camera_services.sh exited nonzero ($status) against successful mocks: $(cat "$err_file")"
fi

if ! grep -q 'launchctl kickstart -k system/com.apple.cmio.AVCAssistant' "$invocations_file"; then
  fail "expected a launchctl kickstart invocation for com.apple.cmio.AVCAssistant"
fi
if ! grep -q 'launchctl kickstart -k gui/' "$invocations_file"; then
  fail "expected a launchctl kickstart invocation for the per-user AppleCameraAssistant agent"
fi
if ! grep -qF "pkill -f $pkill_pattern" "$invocations_file"; then
  fail "expected pkill to be invoked with the documented pattern \"$pkill_pattern\""
fi
echo "PASS: [mocked] launchctl and pkill were invoked with the documented targets, and the script exited zero"

echo
echo "== Mocked failure: a failing launchctl/pkill must not abort the script =="

write_mock launchctl "
echo \"launchctl \$*\" >> '$invocations_file'
exit 1
"
write_mock pkill "
echo \"pkill \$*\" >> '$invocations_file'
exit 1
"

set +e
PATH="$mock_dir:$PATH" bash "$script_path" > "$out_file" 2> "$err_file"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  fail "reset_camera_services.sh exited nonzero ($status) when launchctl/pkill failed -- '|| true' should have absorbed this: $(cat "$err_file")"
fi
if ! grep -q "Done." "$out_file"; then
  fail "expected the completion message even after launchctl/pkill reported failure"
fi
echo "PASS: [mocked] a failing launchctl/pkill does not abort the script; it still completes and exits zero"

echo
echo "All reset_camera_services.sh safety regression checks passed."

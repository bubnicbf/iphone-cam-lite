#!/usr/bin/env bash
# Single entry point for the whole test suite: discovers and runs every
# scripts/test_*.sh regression test deterministically (sorted by
# filename), prints a PASS/FAIL line for each, and exits nonzero if any
# failed. This is what `make test` calls.
#
# Discovery (rather than a hardcoded list) means a newly added
# scripts/test_*.sh file is picked up automatically the next time this
# runs -- no test can be silently left out of the suite.
#
# This runner performs no system-changing operations itself; each
# individual test file is responsible for mocking any external command it
# needs (launchctl, pkill, open, pgrep, osascript, ...), so running the
# full suite here never launches Zoom, Teams, System Events automation,
# or touches real camera/media services.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

test_files=()
while IFS= read -r -d '' f; do
  test_files+=("$f")
done < <(find "$repo_root/scripts" -maxdepth 1 -name 'test_*.sh' -print0 | sort -z)

if [[ ${#test_files[@]} -eq 0 ]]; then
  echo "FAIL: no scripts/test_*.sh files were found -- test discovery is broken" >&2
  exit 1
fi

pass_count=0
fail_count=0
failed_names=()

for test_file in "${test_files[@]}"; do
  test_name="$(basename "$test_file")"
  echo "== $test_name =="
  if bash "$test_file"; then
    echo "RESULT: PASS -- $test_name"
    pass_count=$((pass_count + 1))
  else
    echo "RESULT: FAIL -- $test_name" >&2
    fail_count=$((fail_count + 1))
    failed_names+=("$test_name")
  fi
  echo
done

echo "== Summary =="
echo "$pass_count passed, $fail_count failed, ${#test_files[@]} total"

if [[ $fail_count -gt 0 ]]; then
  echo "Failed tests:" >&2
  for name in "${failed_names[@]}"; do
    echo "  - $name" >&2
  done
  exit 1
fi

echo "All tests passed."

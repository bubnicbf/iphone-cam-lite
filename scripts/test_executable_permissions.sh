#!/usr/bin/env bash
# Regression test: every tracked shell script under scripts/ must be
# recorded in the Git index as executable (mode 100755), and AppleScript
# (.scpt) files must not be accidentally marked executable unless they
# themselves carry an executable shebang.
#
# This test only inspects file contents, filesystem permission bits, and
# the Git index -- it never runs any script, so Zoom, Teams, caffeinate,
# camera services, AppleScript UI automation, and the prerequisite checker
# are never invoked.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail_files=()

git_mode_for() {
  # Prints the Git index mode (e.g. 100755) for a tracked path, or empty
  # if the path is not tracked.
  git ls-files --stage -- "$1" | awk '{print $1}'
}

has_shebang() {
  local file="$1" first_line=""
  IFS= read -r first_line < "$file" || true
  [[ "$first_line" == \#!* ]]
}

has_shell_shebang() {
  local file="$1" first_line=""
  IFS= read -r first_line < "$file" || true
  [[ "$first_line" =~ ^#\!.*(bash|/bin/sh|env[[:space:]]+sh)([[:space:]]|$) ]]
}

echo "== Checking tracked .sh scripts under scripts/ =="
sh_files="$(git ls-files -- 'scripts/*.sh')"
if [[ -z "$sh_files" ]]; then
  echo "FAIL: no tracked .sh files found under scripts/ (expected at least one)" >&2
  exit 1
fi

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  ok=1

  if [[ ! -f "$file" ]]; then
    echo "  - $file: MISSING from working tree" >&2
    ok=0
  fi

  if [[ $ok -eq 1 ]] && ! has_shell_shebang "$file"; then
    echo "  - $file: missing an appropriate shell shebang (expected bash/sh)" >&2
    ok=0
  fi

  if [[ $ok -eq 1 ]] && [[ ! -x "$file" ]]; then
    echo "  - $file: not executable on the filesystem" >&2
    ok=0
  fi

  mode="$(git_mode_for "$file")"
  if [[ "$mode" != "100755" ]]; then
    echo "  - $file: Git index mode is '${mode:-untracked}', expected 100755" >&2
    ok=0
  fi

  if [[ $ok -eq 1 ]]; then
    echo "  - $file: OK (shebang, filesystem +x, git mode 100755)"
  else
    fail_files+=("$file")
  fi
done <<< "$sh_files"

echo
echo "== Checking tracked .scpt files under scripts/ are not accidentally executable =="
scpt_files="$(git ls-files -- 'scripts/*.scpt')"
if [[ -n "$scpt_files" ]]; then
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    mode="$(git_mode_for "$file")"

    if [[ -f "$file" ]] && has_shebang "$file"; then
      echo "  - $file: has a shebang; executable mode is acceptable (mode: ${mode:-untracked})"
      continue
    fi

    bad=0
    if [[ "$mode" == "100755" ]]; then
      echo "  - $file: unexpectedly tracked as executable (100755) but has no shebang" >&2
      bad=1
    fi
    if [[ -f "$file" && -x "$file" ]]; then
      echo "  - $file: unexpectedly executable on the filesystem but has no shebang" >&2
      bad=1
    fi

    if [[ $bad -eq 1 ]]; then
      fail_files+=("$file")
    else
      echo "  - $file: OK (mode ${mode:-untracked}, no shebang, not executable)"
    fi
  done <<< "$scpt_files"
else
  echo "  (no tracked .scpt files found)"
fi

echo
if [[ ${#fail_files[@]} -gt 0 ]]; then
  echo "FAIL: incorrect executable mode/shebang for: ${fail_files[*]}" >&2
  exit 1
fi

echo "All tracked scripts under scripts/ have correct executable permissions."

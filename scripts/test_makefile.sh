#!/usr/bin/env bash
# Regression test for the root Makefile.
#
# Guards against the Makefile being accidentally re-committed with Markdown
# wrapper content (a "## Makefile" heading / ```make fence), and confirms
# that `make` can still parse it and that the expected targets are defined.
#
# This test never executes a target's recipe body — it only uses `make -n`
# (dry-run) so setup scripts, Zoom/Teams, keepawake, and camera-reset are
# never actually launched. Safe to run in CI or locally on macOS Bash.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makefile="$repo_root/Makefile"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [[ ! -f "$makefile" ]]; then
  fail "Makefile not found at $makefile"
fi

# 1. The Makefile must not contain Markdown fence/heading artifacts.
if grep -nE '^(##[[:space:]]|```)' "$makefile" > /dev/null; then
  grep -nE '^(##[[:space:]]|```)' "$makefile" >&2
  fail "Makefile contains Markdown fence/heading lines (e.g. '## Makefile' or \`\`\`make)"
fi
echo "PASS: no Markdown fences found in Makefile"

# 2. The Makefile must be parsable by make (this is what 'missing separator'
#    failures break). -n means dry-run: no recipe is executed.
if ! make -n -f "$makefile" -C "$repo_root" > /tmp/test_makefile_parse.$$ 2>&1; then
  cat /tmp/test_makefile_parse.$$ >&2
  rm -f /tmp/test_makefile_parse.$$
  fail "make failed to parse the Makefile (e.g. 'missing separator')"
fi
rm -f /tmp/test_makefile_parse.$$
echo "PASS: make parses the Makefile without error"

# 3. Every expected target must exist and dry-run cleanly (no execution).
expected_targets=(setup zoom teams keepawake reset-camera)
for target in "${expected_targets[@]}"; do
  if ! make -n -f "$makefile" -C "$repo_root" "$target" > /dev/null 2>&1; then
    fail "target '$target' failed to dry-run via 'make -n $target'"
  fi
  echo "PASS: target '$target' dry-runs cleanly"
done

# 4. Recipe lines must be indented with a literal tab, not spaces. A
#    space-indented recipe line is the classic cause of 'missing separator'.
if awk '/^ /{exit 1}' "$makefile"; then
  echo "PASS: no space-indented lines found (recipes use tabs)"
else
  fail "Makefile contains a line indented with spaces instead of a tab"
fi

echo "All Makefile regression checks passed."

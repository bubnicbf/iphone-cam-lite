#!/usr/bin/env bash
# Regression coverage for scripts/build_release.sh: builds a real (but
# synthetic-version) release into an isolated temporary directory, then
# inspects the resulting tar.gz, zip, and SHA256SUMS artifacts. Never
# writes into the repository's own dist/ directory and never commits
# anything. Also confirms malformed/unsafe version input is rejected
# before any artifact is written, and cannot be used to escape the
# intended output directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_script="$repo_root/scripts/build_release.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

if [[ ! -x "$build_script" ]]; then
  fail "scripts/build_release.sh is missing or not executable"
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

output_dir="$work_dir/out"
project_name="iphone-cam-lite"
test_version="0.0.0-test"
version_dir="${project_name}-${test_version}"

echo "== Building a synthetic-version release into an isolated temp directory =="
if ! "$build_script" "$test_version" "$output_dir" > "$work_dir/build_stdout.log" 2> "$work_dir/build_stderr.log"; then
  cat "$work_dir/build_stderr.log" >&2
  fail "build_release.sh exited nonzero for a valid version"
fi
echo "PASS: build_release.sh exited zero for a valid synthetic version"

tar_path="$output_dir/${version_dir}.tar.gz"
zip_path="$output_dir/${version_dir}.zip"
sums_path="$output_dir/${version_dir}-SHA256SUMS.txt"

echo
echo "== Artifact existence and non-emptiness =="
for artifact in "$tar_path" "$zip_path" "$sums_path"; do
  if [[ ! -s "$artifact" ]]; then
    fail "expected artifact missing or empty: $artifact"
  fi
done
echo "PASS: tar.gz, zip, and SHA256SUMS were all created and are nonempty"

echo
echo "== Checksum verification =="
if ! grep -qF "$(basename "$tar_path")" "$sums_path"; then
  fail "SHA256SUMS does not list $(basename "$tar_path")"
fi
if ! grep -qF "$(basename "$zip_path")" "$sums_path"; then
  fail "SHA256SUMS does not list $(basename "$zip_path")"
fi
if ! ( cd "$output_dir" && shasum -a 256 -c "$(basename "$sums_path")" > "$work_dir/shasum_check.log" 2>&1 ); then
  cat "$work_dir/shasum_check.log" >&2
  fail "shasum -c reported a checksum mismatch"
fi
echo "PASS: SHA256SUMS lists both archives and verifies against their actual contents"

echo
echo "== Archive naming and top-level directory =="
if [[ "$(basename "$tar_path")" != "${version_dir}.tar.gz" ]]; then
  fail "tar.gz name does not follow the <project>-<version>.tar.gz convention"
fi
if [[ "$(basename "$zip_path")" != "${version_dir}.zip" ]]; then
  fail "zip name does not follow the <project>-<version>.zip convention"
fi

tar_entries="$(tar -tzf "$tar_path")"
stray_tar="$(echo "$tar_entries" | grep -v "^${version_dir}/" || true)"
if [[ -n "$stray_tar" ]]; then
  fail "tar.gz contains entries outside the '${version_dir}/' top-level directory: $stray_tar"
fi
echo "PASS: tar.gz has exactly one versioned top-level directory"

zip_entries="$(unzip -Z1 "$zip_path")"
stray_zip="$(echo "$zip_entries" | grep -v "^${version_dir}/" || true)"
if [[ -n "$stray_zip" ]]; then
  fail "zip contains entries outside the '${version_dir}/' top-level directory: $stray_zip"
fi
echo "PASS: zip has exactly one versioned top-level directory"

echo
echo "== No absolute paths or parent-directory traversal =="
if echo "$tar_entries" | grep -qE '^/|\.\./'; then
  fail "tar.gz contains an absolute path or parent-directory traversal entry"
fi
if echo "$zip_entries" | grep -qE '^/|\.\./'; then
  fail "zip contains an absolute path or parent-directory traversal entry"
fi
echo "PASS: neither archive contains an absolute path or '../' entry"

echo
echo "== Extraction and required/excluded file checks =="
extract_tar_dir="$work_dir/extract_tar"
extract_zip_dir="$work_dir/extract_zip"
mkdir -p "$extract_tar_dir" "$extract_zip_dir"
tar -xzf "$tar_path" -C "$extract_tar_dir"
unzip -q "$zip_path" -d "$extract_zip_dir"

required_files=(
  "Makefile"
  "README.md"
  "CHANGELOG.md"
  "SECURITY.md"
  "LICENSE"
  "scripts/check_prereqs.sh"
  "scripts/start_zoom.sh"
  "scripts/start_teams.sh"
  "scripts/keepawake.sh"
  "scripts/reset_camera_services.sh"
  "scripts/select_zoom_camera.scpt"
  "scripts/select_teams_camera.scpt"
)
for pkg_root in "$extract_tar_dir/$version_dir" "$extract_zip_dir/$version_dir"; do
  for rel in "${required_files[@]}"; do
    if [[ ! -f "$pkg_root/$rel" ]]; then
      fail "required runtime file missing from package: $rel (in $pkg_root)"
    fi
  done
done
echo "PASS: every required runtime file is present in both extracted archives"

excluded_paths=(
  ".git"
  ".github"
  "tests"
  "dist"
  "_to_delete"
  ".env"
  ".DS_Store"
  "CONTRIBUTING.md"
  "ROADMAP.md"
)
for pkg_root in "$extract_tar_dir/$version_dir" "$extract_zip_dir/$version_dir"; do
  for rel in "${excluded_paths[@]}"; do
    if [[ -e "$pkg_root/$rel" ]]; then
      fail "excluded development path was found in the package: $rel (in $pkg_root)"
    fi
  done
  # No scripts/test_*.sh or build_release.sh should ship in the archive --
  # those are development/release-engineering tooling, not runtime files.
  if compgen -G "$pkg_root/scripts/test_*.sh" > /dev/null 2>&1; then
    fail "found scripts/test_*.sh in the package at $pkg_root -- test scripts must not ship in a release archive"
  fi
  if [[ -e "$pkg_root/scripts/build_release.sh" ]]; then
    fail "found scripts/build_release.sh in the package at $pkg_root -- the packaging script itself must not ship in a release archive"
  fi
done
echo "PASS: excluded development files/directories are absent from both extracted archives"

echo
echo "== Executable modes preserved in the tar archive =="
runnable_scripts=(start_zoom.sh start_teams.sh check_prereqs.sh keepawake.sh reset_camera_services.sh)
for name in "${runnable_scripts[@]}"; do
  f="$extract_tar_dir/$version_dir/scripts/$name"
  if [[ ! -x "$f" ]]; then
    fail "scripts/$name lost its executable mode in the tar.gz archive"
  fi
done
for scpt in select_zoom_camera.scpt select_teams_camera.scpt; do
  f="$extract_tar_dir/$version_dir/scripts/$scpt"
  if [[ -x "$f" ]]; then
    fail "scripts/$scpt should not be executable in the packaged archive"
  fi
done
echo "PASS: runnable shell scripts kept their executable mode, and AppleScript sources stayed non-executable, in the tar.gz archive"

echo
echo "== Packaged shell scripts still pass bash -n =="
while IFS= read -r -d '' f; do
  if ! bash -n "$f"; then
    fail "bash -n failed for packaged script: $f"
  fi
done < <(find "$extract_tar_dir/$version_dir/scripts" -name '*.sh' -print0)
echo "PASS: every packaged .sh file passes 'bash -n'"

echo
echo "== make -n against the extracted package =="
if ! ( cd "$extract_tar_dir/$version_dir" && make -n setup zoom teams keepawake reset-camera > /dev/null 2>&1 ); then
  fail "'make -n' failed against the extracted package's Makefile"
fi
echo "PASS: 'make -n' dry-runs the extracted package's operational targets cleanly"

echo
echo "== Malformed and unsafe version rejection =="
bad_versions=("" "1.2" "1.2.3.4" "abc" "1.2.3/../evil" "1.2.3; rm -rf /" " 1.2.3" "v" "1.2.3 ")
bad_index=0
for bad in "${bad_versions[@]}"; do
  bad_index=$((bad_index + 1))
  reject_out_dir="$work_dir/reject_$bad_index"
  set +e
  "$build_script" "$bad" "$reject_out_dir" > "$work_dir/reject_stdout.log" 2> "$work_dir/reject_stderr.log"
  reject_status=$?
  set -e
  if [[ $reject_status -eq 0 ]]; then
    fail "build_release.sh accepted an invalid version: \"$bad\""
  fi
  if [[ -d "$reject_out_dir" ]] && find "$reject_out_dir" -mindepth 1 -print -quit | grep -q .; then
    fail "build_release.sh left artifacts behind for a rejected version: \"$bad\""
  fi
done
echo "PASS: every malformed/unsafe version string was rejected with no artifacts written"

echo
echo "== A version cannot be used to escape the intended output directory =="
traversal_dir="$work_dir/traversal_out"
canary_path="/tmp/build_release_traversal_canary_$$"
rm -f "$canary_path"
set +e
"$build_script" "../../../../../../tmp/build_release_traversal_canary_$$" "$traversal_dir" > "$work_dir/traversal_stdout.log" 2> "$work_dir/traversal_stderr.log"
traversal_status=$?
set -e
if [[ $traversal_status -eq 0 ]]; then
  fail "build_release.sh accepted a path-traversal version string"
fi
if [[ -e "$canary_path" ]]; then
  rm -rf "$canary_path"
  fail "a path-traversal version string escaped the intended output directory"
fi
echo "PASS: a path-traversal version string is rejected and cannot escape the output directory"

echo
echo "All release-packaging regression checks passed."

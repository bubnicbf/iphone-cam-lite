#!/usr/bin/env bash
# Builds reproducible release artifacts for iphone-cam-lite: a tar.gz
# archive, a zip archive, and a SHA256SUMS file covering both, each named
# "<project>-<version>.*". Packaging always happens in a temporary staging
# directory that is removed afterward -- this script never packages
# directly from, or overwrites, the working tree.
#
# Usage: scripts/build_release.sh <version> [output_dir]
#
# See usage() below for the full argument description.
set -euo pipefail

PROJECT_NAME="iphone-cam-lite"

usage() {
  cat <<'EOF'
Usage: scripts/build_release.sh <version> [output_dir]

  <version>     Required. A semantic version, optionally prefixed with "v"
                (e.g. "1.2.0" or "v1.2.0"). Rejected if empty, malformed,
                or unsafe for use in a filesystem path or archive entry
                name. The leading "v" (if present) is accepted but the
                archive/directory name is always normalized to the bare
                version, so "v1.2.0" and "1.2.0" produce identical output.

  [output_dir]  Optional. Where to write the release artifacts. Defaults
                to "dist/" under the repository root. Can also be set via
                the RELEASE_OUTPUT_DIR environment variable (useful for
                tests and CI); an explicit argument takes precedence over
                the variable.

Builds a tar.gz archive, a zip archive, and a "<project>-<version>-
SHA256SUMS.txt" checksum file covering both, each containing exactly one
top-level directory named "<project>-<version>". Packaging happens in a
temporary staging directory (never directly from the working tree, and
never overwriting source files); the staging directory is always removed
afterward, even on failure.
EOF
}

fail() {
  echo "build_release.sh: error: $1" >&2
  exit 1
}

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  usage >&2
  fail "a version argument is required"
fi

raw_version="$1"
output_dir_arg="${2:-}"

# Accept an optional leading "v" (as in a Git tag, e.g. "v1.2.0") but
# normalize the archive/directory name to the bare version consistently.
version_no_v="${raw_version#v}"

# Strict, conservative semantic-version validation: MAJOR.MINOR.PATCH with
# an optional -prerelease and/or +build-metadata suffix, using only
# characters that are always safe in a single path segment and an archive
# entry name. Anything else -- empty, whitespace, slashes, "..", shell
# metacharacters, a non-numeric leading component -- is rejected outright
# rather than silently coerced into something "close enough".
semver_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?$'
if [[ ! "$version_no_v" =~ $semver_pattern ]]; then
  fail "invalid version \"$raw_version\" -- expected MAJOR.MINOR.PATCH, optionally prefixed with 'v' and/or suffixed with -prerelease/+build metadata, e.g. \"1.2.0\" or \"v1.2.0-rc.1\""
fi

# Belt-and-suspenders: even though the regex above already excludes them,
# explicitly refuse path-separator/traversal/whitespace characters so a
# future pattern change can't silently reopen this.
case "$version_no_v" in
  */*|*'..'*|*' '*)
    fail "invalid version \"$raw_version\" -- must not contain '/', '..', or whitespace"
    ;;
esac

version_dir_name="${PROJECT_NAME}-${version_no_v}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Output directory: explicit argument > RELEASE_OUTPUT_DIR env var >
# "dist/" under the repo root. Resolved to an absolute path so the
# tar/zip/shasum invocations below are never sensitive to the caller's
# current working directory.
if [[ -n "$output_dir_arg" ]]; then
  output_dir="$output_dir_arg"
elif [[ -n "${RELEASE_OUTPUT_DIR:-}" ]]; then
  output_dir="$RELEASE_OUTPUT_DIR"
else
  output_dir="$repo_root/dist"
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

for tool in tar zip shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "required tool '$tool' was not found on PATH"
  fi
done

staging_root="$(mktemp -d)"
trap 'rm -rf "$staging_root"' EXIT

package_dir="$staging_root/$version_dir_name"
mkdir -p "$package_dir"

# Copy only the runtime files users actually need -- never the whole
# working tree, and never anything development-only (.git, .github,
# tests/, dist/, scripts/test_*.sh, this script itself, editor/temp/log
# files, _to_delete/, or machine-specific config). This list is
# deliberately explicit rather than "everything except an exclude
# pattern", so a stray new dev-only file added later can never silently
# end up in a release archive.
copy_file() {
  local rel="$1"
  if [[ -f "$repo_root/$rel" ]]; then
    mkdir -p "$package_dir/$(dirname "$rel")"
    cp -p "$repo_root/$rel" "$package_dir/$rel"
  fi
}

copy_file "Makefile"
copy_file "README.md"
copy_file "CHANGELOG.md"
copy_file "SECURITY.md"
copy_file "LICENSE"
copy_file "scripts/check_prereqs.sh"
copy_file "scripts/start_zoom.sh"
copy_file "scripts/start_teams.sh"
copy_file "scripts/keepawake.sh"
copy_file "scripts/reset_camera_services.sh"
copy_file "scripts/select_zoom_camera.scpt"
copy_file "scripts/select_teams_camera.scpt"

if [[ ! -f "$package_dir/Makefile" || ! -f "$package_dir/README.md" ]]; then
  fail "required runtime files (Makefile, README.md) were not found in the repository -- refusing to build an incomplete release"
fi

# cp -p above already preserves each source file's executable bit, but
# assert it explicitly so a future umask/tooling change can't silently
# ship a non-executable launcher.
for runnable in start_zoom.sh start_teams.sh check_prereqs.sh keepawake.sh reset_camera_services.sh; do
  f="$package_dir/scripts/$runnable"
  if [[ -f "$f" && ! -x "$f" ]]; then
    chmod +x "$f"
  fi
done

tar_path="$output_dir/${version_dir_name}.tar.gz"
zip_path="$output_dir/${version_dir_name}.zip"
sums_path="$output_dir/${version_dir_name}-SHA256SUMS.txt"

rm -f "$tar_path" "$zip_path" "$sums_path"

# Both archives are built from inside the staging root, referencing only
# the versioned directory name, so the only top-level entry in either
# archive is that directory -- no absolute paths, no staging-directory
# name leaking in, no parent-directory traversal entries.
( cd "$staging_root" && tar -czf "$tar_path" "$version_dir_name" )
( cd "$staging_root" && zip -rq "$zip_path" "$version_dir_name" )

if [[ ! -s "$tar_path" ]]; then
  fail "tar.gz archive was not created or is empty: $tar_path"
fi
if [[ ! -s "$zip_path" ]]; then
  fail "zip archive was not created or is empty: $zip_path"
fi

( cd "$output_dir" && shasum -a 256 "$(basename "$tar_path")" "$(basename "$zip_path")" > "$sums_path" )

if [[ ! -s "$sums_path" ]]; then
  fail "SHA256SUMS file was not created or is empty: $sums_path"
fi

echo "Release artifacts for $PROJECT_NAME $version_no_v:"
echo "  $tar_path"
echo "  $zip_path"
echo "  $sums_path"

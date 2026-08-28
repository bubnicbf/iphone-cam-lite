#!/usr/bin/env bash
# Builds a distributable IPhoneCamLite.app bundle from the Swift package
# and packages it into a versioned .zip plus a SHA256SUMS file, replacing
# the old build_release.sh (which packaged the now-retired shell scripts).
#
# This intentionally does NOT require Xcode or a third-party project
# generator: it drives `swift build` directly and assembles a standard
# macOS app bundle by hand from Resources/Info.plist,
# Resources/PrivacyInfo.xcprivacy, and Resources/Assets.xcassets. If Xcode
# command line tools are present, `actool` compiles the asset catalog
# properly; otherwise the raw catalog is copied and a warning is printed
# (the app still runs -- the menu bar icon is an SF Symbol, not a custom
# asset -- only the Dock/Finder icon artwork is affected).
#
# Usage: scripts/package_app.sh <version> [output_dir]
set -euo pipefail

PROJECT_NAME="IPhoneCamLite"
BUNDLE_IDENTIFIER="com.iphonecamlite.app"

usage() {
  cat <<'EOF'
Usage: scripts/package_app.sh <version> [output_dir]

  <version>     Required. A semantic version, optionally prefixed with "v"
                (e.g. "1.2.0" or "v1.2.0").
  [output_dir]  Optional. Where to write release artifacts. Defaults to
                "dist/" under the repository root. Can also be set via the
                RELEASE_OUTPUT_DIR environment variable.

Builds IPhoneCamLite in release configuration, assembles
IPhoneCamLite.app, and packages it into
"<output_dir>/IPhoneCamLite-<version>.zip" plus a matching
"-SHA256SUMS.txt" file.
EOF
}

fail() {
  echo "package_app.sh: error: $1" >&2
  exit 1
}

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  usage >&2
  fail "a version argument is required"
fi

raw_version="$1"
output_dir_arg="${2:-}"
version_no_v="${raw_version#v}"

semver_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?$'
if [[ ! "$version_no_v" =~ $semver_pattern ]]; then
  fail "invalid version \"$raw_version\" -- expected MAJOR.MINOR.PATCH, optionally prefixed with 'v' and/or suffixed with -prerelease/+build metadata"
fi
case "$version_no_v" in
  */*|*'..'*|*' '*)
    fail "invalid version \"$raw_version\" -- must not contain '/', '..', or whitespace"
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "$output_dir_arg" ]]; then
  output_dir="$output_dir_arg"
elif [[ -n "${RELEASE_OUTPUT_DIR:-}" ]]; then
  output_dir="$RELEASE_OUTPUT_DIR"
else
  output_dir="$repo_root/dist"
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

for tool in swift zip shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    fail "required tool '$tool' was not found on PATH"
  fi
done

echo "▶ Building $PROJECT_NAME (release)…"
( cd "$repo_root" && swift build -c release --product "$PROJECT_NAME" )
bin_path="$(cd "$repo_root" && swift build -c release --show-bin-path)"
executable_path="$bin_path/$PROJECT_NAME"
if [[ ! -x "$executable_path" ]]; then
  fail "expected build product not found or not executable: $executable_path"
fi

staging_root="$(mktemp -d)"
trap 'rm -rf "$staging_root"' EXIT

app_bundle="$staging_root/${PROJECT_NAME}.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

cp -p "$executable_path" "$app_bundle/Contents/MacOS/$PROJECT_NAME"
chmod +x "$app_bundle/Contents/MacOS/$PROJECT_NAME"

# Info.plist, with the requested version substituted in.
info_plist_src="$repo_root/Resources/Info.plist"
[[ -f "$info_plist_src" ]] || fail "missing $info_plist_src"
cp -p "$info_plist_src" "$app_bundle/Contents/Info.plist"
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version_no_v" "$app_bundle/Contents/Info.plist"
else
  echo "ℹ PlistBuddy not found -- shipping Info.plist's checked-in version string as-is." >&2
fi

# Privacy manifest.
privacy_src="$repo_root/Resources/PrivacyInfo.xcprivacy"
[[ -f "$privacy_src" ]] || fail "missing $privacy_src"
cp -p "$privacy_src" "$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"

# Asset catalog: compile with actool when the Xcode toolchain is present,
# otherwise copy the raw catalog and warn (functionality is unaffected --
# only Dock/Finder icon artwork depends on this).
assets_src="$repo_root/Resources/Assets.xcassets"
if [[ -d "$assets_src" ]]; then
  if command -v xcrun >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
    echo "▶ Compiling asset catalog with actool…"
    xcrun actool "$assets_src" \
      --compile "$app_bundle/Contents/Resources" \
      --platform macosx \
      --minimum-deployment-target 13.0 \
      --app-icon AppIcon \
      --output-partial-info-plist "$staging_root/assetcatalog_generated_info.plist" \
      >/dev/null
  else
    echo "⚠ actool not found (requires Xcode) -- copying the raw asset catalog instead of compiling it. The app still runs; only Dock/Finder icon artwork is affected." >&2
    cp -R "$assets_src" "$app_bundle/Contents/Resources/Assets.xcassets"
  fi
fi

zip_path="$output_dir/${PROJECT_NAME}-${version_no_v}.zip"
sums_path="$output_dir/${PROJECT_NAME}-${version_no_v}-SHA256SUMS.txt"
rm -f "$zip_path" "$sums_path"

( cd "$staging_root" && zip -rq "$zip_path" "${PROJECT_NAME}.app" )
if [[ ! -s "$zip_path" ]]; then
  fail "zip archive was not created or is empty: $zip_path"
fi

( cd "$output_dir" && shasum -a 256 "$(basename "$zip_path")" > "$sums_path" )
if [[ ! -s "$sums_path" ]]; then
  fail "SHA256SUMS file was not created or is empty: $sums_path"
fi

echo "Release artifacts for $PROJECT_NAME $version_no_v:"
echo "  $zip_path"
echo "  $sums_path"

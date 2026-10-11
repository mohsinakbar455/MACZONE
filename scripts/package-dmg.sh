#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
app_path="$PWD/build/MACZONE.app"
if [[ ! -d "$app_path" ]]; then
  printf 'Build the app first with bash scripts/build.sh\n' >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
archive="$PWD/build/MACZONE-${version}-arm64-preview.dmg"
stage=$(mktemp -d "${TMPDIR:-/tmp}/maczone-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT

ditto "$app_path" "$stage/MACZONE.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "MACZONE ${version}" -srcfolder "$stage" -format UDZO -ov "$archive"
printf 'Created %s\n' "$archive"
shasum -a 256 "$archive"

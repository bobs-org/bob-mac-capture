#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/bundle.sh [--identity IDENTITY] [--configuration debug|release] [--output DIR]

Assembles and signs "Bob Mac Capture.app" from the SwiftPM executable.
Use --identity "-" for an ad-hoc development signature.
USAGE
}

identity="${CODESIGN_IDENTITY:--}"
configuration="release"
output_dir="${PWD}/.build/bundle"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      identity="${2:?missing identity}"
      shift 2
      ;;
    --configuration)
      configuration="${2:?missing configuration}"
      shift 2
      ;;
    --output)
      output_dir="${2:?missing output dir}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "${configuration}" in
  debug|release) ;;
  *)
    printf 'Unsupported configuration: %s\n' "${configuration}" >&2
    exit 64
    ;;
esac

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_name="Bob Mac Capture.app"
app_path="${output_dir}/${app_name}"

cd "${package_root}"
swift build --configuration "${configuration}" --product BobMacCapture
binary_path="$(swift build --configuration "${configuration}" --show-bin-path)/BobMacCapture"

rm -rf "${app_path}"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
cp "${binary_path}" "${app_path}/Contents/MacOS/BobMacCapture"
cp "${package_root}/Resources/Info.plist" "${app_path}/Contents/Info.plist"
chmod 0755 "${app_path}/Contents/MacOS/BobMacCapture"

/usr/bin/codesign --force --sign "${identity}" --timestamp=none \
  "${app_path}/Contents/MacOS/BobMacCapture"
/usr/bin/codesign --force --deep --strict --options runtime --sign "${identity}" \
  --timestamp=none "${app_path}"
/usr/bin/codesign --verify --deep --strict "${app_path}"

printf '%s\n' "${app_path}"

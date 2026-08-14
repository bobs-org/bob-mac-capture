#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/xcode-swift.sh <swift arguments...>

Resolves and runs Swift through `/usr/bin/xcrun` using the macOS SDK and default
toolchain from the selected full Xcode 26+ developer directory, forwarding every
argument and the exit status unchanged. This ignores a `swift` executable earlier on
PATH and any ambient TOOLCHAINS override, so `import XCTest` and other Xcode-only
frameworks resolve consistently across build, test, format, and bundle commands.

Honors DEVELOPER_DIR / the active `xcode-select` choice so a nonstandard Xcode
application name still works. Fails before invoking Swift, with an actionable message,
when a full Xcode 26+ developer directory, its macOS 26+ SDK, or its Swift executable
cannot be resolved.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

readonly min_sdk_major=26
readonly select_hint="  sudo xcode-select --switch /Applications/Xcode.app"

fail() {
  printf 'error: %s\n' "$1" >&2
  shift
  for line in "$@"; do
    printf '  %s\n' "${line}" >&2
  done
  exit 69
}

developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "${developer_dir}" ]]; then
  if ! developer_dir="$(/usr/bin/xcode-select --print-path 2>/dev/null)"; then
    fail "no Xcode developer directory is selected" \
      "Install Xcode 26+ from the App Store, then run:" \
      "${select_hint}"
  fi
fi

case "${developer_dir}" in
  */Contents/Developer) ;;
  *)
    fail "the selected developer directory is not a full Xcode installation: ${developer_dir}" \
      "Standalone Command Line Tools do not include XCTest and other Xcode-only frameworks." \
      "Select the full Xcode application:" \
      "${select_hint}" \
      "Or scope the fix to one shell without changing the system default:" \
      "  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"
    ;;
esac

# Ignore an ambient alternate toolchain or SDK root selection; resolve everything from
# the validated developer directory and the default Xcode toolchain instead.
unset TOOLCHAINS
unset SDKROOT
export DEVELOPER_DIR="${developer_dir}"

xcrun=(/usr/bin/xcrun --sdk macosx --toolchain default)

sdk_version="$("${xcrun[@]}" --show-sdk-version 2>/dev/null)" || {
  fail "could not resolve the macOS SDK from ${developer_dir}" \
    "Confirm a full Xcode 26+ is installed and selected:" \
    "${select_hint}"
}

sdk_major="${sdk_version%%.*}"
if [[ -z "${sdk_major}" || "${sdk_major}" -lt "${min_sdk_major}" ]]; then
  fail "the selected Xcode's macOS SDK is ${sdk_version}, but ${min_sdk_major}+ is required" \
    "Developer directory: ${developer_dir}" \
    "Install Xcode 26+ and select it:" \
    "${select_hint}"
fi

"${xcrun[@]}" --find swift >/dev/null 2>&1 || {
  fail "could not resolve swift from the Xcode 26+ toolchain at ${developer_dir}" \
    "Select a full Xcode 26+ installation:" \
    "${select_hint}"
}

exec "${xcrun[@]}" swift "$@"

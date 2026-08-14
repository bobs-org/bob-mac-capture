#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/xcode-swift.sh <swift arguments...>

Resolves and runs Swift through `/usr/bin/xcrun` using the macOS SDK and default
toolchain from the selected Apple developer tools, forwarding every argument and the
exit status unchanged. This ignores a `swift` executable earlier on PATH and any
ambient TOOLCHAINS override, so build, test, format, and bundle commands use the same
Apple Swift toolchain.

Honors DEVELOPER_DIR / the active `xcode-select` choice. Accepts either Command Line
Tools for Xcode 26+ or a full Xcode 26+ developer directory when the selected tools can
resolve a macOS 26+ SDK and Apple Swift executable. Fails before invoking Swift, with an
actionable message, when those requirements are not met.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

readonly min_sdk_major=26
readonly command_line_tools_dir="/Library/Developer/CommandLineTools"
readonly select_clt_hint="  sudo xcode-select --switch /Library/Developer/CommandLineTools"
readonly select_xcode_hint="  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"

fail() {
  printf 'error: %s\n' "$1" >&2
  shift
  for line in "$@"; do
    printf '  %s\n' "${line}" >&2
  done
  exit 69
}

developer_source() {
  case "$1" in
    "${command_line_tools_dir}"|"${command_line_tools_dir}/"*) printf 'Command Line Tools' ;;
    */Contents/Developer|*/Contents/Developer/) printf 'Xcode' ;;
    *) printf 'Apple developer tools' ;;
  esac
}

fail_with_remedy() {
  source_name="$1"
  message="$2"
  shift 2

  case "${source_name}" in
    "Command Line Tools")
      fail "${message}" "$@" \
        "Install or update Command Line Tools for Xcode ${min_sdk_major}+:" \
        "${select_clt_hint}" \
        "Or select a compatible full Xcode installation:" \
        "${select_xcode_hint}"
      ;;
    "Xcode")
      fail "${message}" "$@" \
        "Install Xcode ${min_sdk_major}+ and select it:" \
        "${select_xcode_hint}" \
        "Or scope the selection to one shell:" \
        "  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"
      ;;
    *)
      fail "${message}" "$@" \
        "Select Command Line Tools for Xcode ${min_sdk_major}+:" \
        "${select_clt_hint}" \
        "Or select a compatible full Xcode installation:" \
        "${select_xcode_hint}"
      ;;
  esac
}

developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "${developer_dir}" ]]; then
  if ! developer_dir="$(/usr/bin/xcode-select --print-path 2>/dev/null)"; then
    fail_with_remedy "Apple developer tools" "no Apple developer tools directory is selected"
  fi
fi

source_name="$(developer_source "${developer_dir}")"

if [[ ! -d "${developer_dir}" ]]; then
  fail_with_remedy "${source_name}" "the selected ${source_name} directory does not exist: ${developer_dir}"
fi

# Ignore an ambient alternate toolchain or SDK root selection; resolve everything from
# the validated developer directory and the default Apple toolchain instead.
unset TOOLCHAINS
unset SDKROOT
export DEVELOPER_DIR="${developer_dir}"

xcrun=(/usr/bin/xcrun --sdk macosx --toolchain default)

sdk_version="$("${xcrun[@]}" --show-sdk-version 2>/dev/null)" || {
  fail_with_remedy "${source_name}" "could not resolve the macOS SDK from the selected ${source_name}" \
    "Developer directory: ${developer_dir}"
}

sdk_major="${sdk_version%%.*}"
if [[ ! "${sdk_major}" =~ ^[0-9]+$ || "${sdk_major}" -lt "${min_sdk_major}" ]]; then
  fail_with_remedy "${source_name}" \
    "the selected ${source_name} macOS SDK is ${sdk_version}, but ${min_sdk_major}+ is required" \
    "Developer directory: ${developer_dir}"
fi

swift_path="$("${xcrun[@]}" --find swift 2>/dev/null)" || {
  fail_with_remedy "${source_name}" "could not resolve swift from the selected ${source_name}" \
    "Developer directory: ${developer_dir}"
}

if [[ -z "${swift_path}" || ! -x "${swift_path}" ]]; then
  fail_with_remedy "${source_name}" \
    "the selected ${source_name} swift executable is not usable: ${swift_path:-<empty>}" \
    "Developer directory: ${developer_dir}"
fi

exec "${xcrun[@]}" swift "$@"

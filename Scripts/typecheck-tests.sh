#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/typecheck-tests.sh

Type-check all SwiftPM test targets. On Macs with Command Line Tools but no XCTest,
uses a type-check-only XCTest stub; CI still builds and runs the tests.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
cd "${repo_root}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'error: typecheck-tests requires macOS and the Apple toolchain\n' >&2
  exit 69
fi

./Scripts/xcode-swift.sh build

readonly module_dir="$(./Scripts/xcode-swift.sh build --show-bin-path)/Modules"
readonly target_triple="$(uname -m)-apple-macosx26.0"

unset TOOLCHAINS
unset SDKROOT
readonly swiftc_path="$(/usr/bin/xcrun --sdk macosx --toolchain default --find swiftc)"
readonly sdk_path="$(/usr/bin/xcrun --sdk macosx --toolchain default --show-sdk-path)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
probe_file="${tmp_dir}/import-xctest.swift"
printf 'import XCTest\n' > "${probe_file}"

if "${swiftc_path}" -typecheck -swift-version 5 -sdk "${sdk_path}" -target "${target_triple}" \
  "${probe_file}" >/dev/null 2>&1; then
  ./Scripts/xcode-swift.sh build --build-tests
  exit $?
fi

stub_dir="${repo_root}/.build/xctest-typecheck-stub"
mkdir -p "${stub_dir}"
"${swiftc_path}" \
  -emit-module \
  -parse-as-library \
  -module-name XCTest \
  -swift-version 5 \
  -sdk "${sdk_path}" \
  -target "${target_triple}" \
  -emit-module-path "${stub_dir}/XCTest.swiftmodule" \
  "${script_dir}/typecheck/XCTest.swift"

typecheck_target() {
  local target_name="$1"
  local log_file="${tmp_dir}/${target_name}.log"
  local status
  local -a files=()

  while IFS= read -r -d '' source_file; do
    files+=("${source_file}")
  done < <(find "Tests/${target_name}" -name '*.swift' -print0)

  if "${swiftc_path}" \
    -typecheck \
    -swift-version 5 \
    -sdk "${sdk_path}" \
    -module-name "${target_name}" \
    -target "${target_triple}" \
    -I "${stub_dir}" \
    -I "${module_dir}" \
    -wmo \
    "${files[@]}" >"${log_file}" 2>&1; then
    return 0
  else
    status=$?
  fi

  if grep -Eiq -- '(-wmo.*(unknown|unsupported|not supported|invalid)|((unknown|unsupported|not supported|invalid).*-wmo))' \
    "${log_file}"; then
    if "${swiftc_path}" \
      -typecheck \
      -swift-version 5 \
      -sdk "${sdk_path}" \
      -module-name "${target_name}" \
      -target "${target_triple}" \
      -I "${stub_dir}" \
      -I "${module_dir}" \
      -j "$(sysctl -n hw.ncpu)" \
      "${files[@]}" >"${log_file}" 2>&1; then
      return 0
    else
      status=$?
    fi
  fi

  cat "${log_file}" >&2
  return "${status}"
}

failed=0
for target in \
  BobMacCaptureTests \
  BobMacCaptureInstallHelperTests \
  CaptureCoreTests \
  RefsCoreTests; do
  if typecheck_target "${target}"; then
    printf 'PASS %s\n' "${target}"
  else
    printf 'FAIL %s\n' "${target}"
    failed=1
  fi
done

printf 'Type-check only: macOS test targets were checked against a stub; CI still runs the tests.\n'
exit "${failed}"

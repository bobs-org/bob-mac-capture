#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/install.sh [--identity IDENTITY] [--target /Applications|~/Applications]

Builds a staged signed app bundle, replaces only the target Bob Mac Capture.app, and
verifies the installed bundle identifier and signature.
USAGE
}

identity="${CODESIGN_IDENTITY:--}"
target_dir="${HOME}/Applications"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      identity="${2:?missing identity}"
      shift 2
      ;;
    --target)
      target_dir="${2:?missing target}"
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

case "${target_dir}" in
  "~/"*) target_dir="${HOME}/${target_dir#"~/"}" ;;
esac

if [[ "${target_dir}" != "/Applications" && "${target_dir}" != "${HOME}/Applications" ]]; then
  printf 'Refusing to install outside /Applications or ~/Applications: %s\n' "${target_dir}" >&2
  exit 64
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_root="${package_root}/.build/install-bundle"
app_name="Bob Mac Capture.app"
staged_app="$("${package_root}/Scripts/bundle.sh" --identity "${identity}" --output "${bundle_root}")"
install_path="${target_dir}/${app_name}"
tmp_path="${target_dir}/.${app_name}.$$"

mkdir -p "${target_dir}"
rm -rf "${tmp_path}"
cp -R "${staged_app}" "${tmp_path}"
/usr/bin/codesign --verify --deep --strict "${tmp_path}"

identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${tmp_path}/Contents/Info.plist")"
if [[ "${identifier}" != "org.bobs.bob-mac-capture" ]]; then
  printf 'Unexpected bundle identifier: %s\n' "${identifier}" >&2
  exit 65
fi

rm -rf "${install_path}"
mv "${tmp_path}" "${install_path}"
/usr/bin/codesign --verify --deep --strict "${install_path}"
printf '%s\n' "${install_path}"

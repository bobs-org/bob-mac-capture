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
staged_app="${bundle_root}/${app_name}"
install_path="${target_dir}/${app_name}"
tmp_path="${target_dir}/.${app_name}.$$"
backup_path="${target_dir}/.${app_name}.previous.$$"

"${package_root}/Scripts/bundle.sh" --identity "${identity}" --output "${bundle_root}" >&2

# Verify the staged bundle fully before touching the install path, then swap it in via
# a rename-with-backup so an interruption mid-install always leaves a recoverable state:
# either the previous app is still at install_path, or it is sitting at backup_path
# ready to be restored.
mkdir -p "${target_dir}"
rm -rf "${tmp_path}"
cp -R "${staged_app}" "${tmp_path}"
/usr/bin/codesign --verify --deep --strict "${tmp_path}"

identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${tmp_path}/Contents/Info.plist")"
if [[ "${identifier}" != "org.bobs.bob-mac-capture" ]]; then
  printf 'Unexpected bundle identifier: %s\n' "${identifier}" >&2
  rm -rf "${tmp_path}"
  exit 65
fi

restore_backup() {
  if [[ -e "${backup_path}" ]]; then
    rm -rf "${install_path}"
    mv "${backup_path}" "${install_path}"
    printf 'Restored the previous install at %s\n' "${install_path}" >&2
  fi
}

rm -rf "${backup_path}"
if [[ -e "${install_path}" ]]; then
  mv "${install_path}" "${backup_path}"
fi

if ! mv "${tmp_path}" "${install_path}"; then
  printf 'Failed to move the staged bundle into place\n' >&2
  rm -rf "${tmp_path}"
  restore_backup
  exit 70
fi

if ! /usr/bin/codesign --verify --deep --strict "${install_path}"; then
  printf 'Post-install signature verification failed\n' >&2
  rm -rf "${install_path}"
  restore_backup
  exit 71
fi

rm -rf "${backup_path}" "${tmp_path}"
printf '%s\n' "${install_path}"

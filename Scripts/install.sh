#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/install.sh [--identity IDENTITY] [--target /Applications|~/Applications]
       [--print-resolved-identity]

Builds a staged signed app bundle, replaces only the target Bob Mac Capture.app,
verifies the installed bundle identifier and signature, and restarts a copy that
was already running from that exact install path.

--print-resolved-identity prints the signing identity that would be used and
exits without touching anything. Useful for read-only verification on the Mac.
USAGE
}

# Name of the stable self-signed code-signing identity (see README › Signing).
# Signing with it keeps the Accessibility and notification grants across
# reinstalls. Created once by Bryan in Keychain Access; never by this script.
stable_identity_name="Bob Mac Capture Local"

# Prints the identity `security find-identity` resolves to: the stable identity
# when the keychain holds it, "-" (ad-hoc) otherwise. Takes no action.
# Kept as a standalone function so it can be exercised on its own.
find_stored_signing_identity() {
  if /usr/bin/security find-identity -p codesigning 2>/dev/null \
    | grep -q "\"${stable_identity_name}\""; then
    printf '%s\n' "${stable_identity_name}"
  else
    printf '%s\n' "-"
  fi
}

# A non-empty --identity wins, including "-". Otherwise a non-empty
# CODESIGN_IDENTITY wins. Empty in both places means "resolve".
cli_identity=""
print_resolved_identity_only=false
target_dir="${HOME}/Applications"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      cli_identity="${2-}"
      shift 2
      ;;
    --target)
      target_dir="${2:?missing target}"
      shift 2
      ;;
    --print-resolved-identity)
      print_resolved_identity_only=true
      shift
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

identity="${cli_identity}"
if [[ -z "${identity}" && -n "${CODESIGN_IDENTITY:-}" ]]; then
  identity="${CODESIGN_IDENTITY}"
fi

# Resolve a still-empty identity against the keychain: the stable identity when
# it exists, ad-hoc with a loud warning otherwise. bundle.sh keeps its own
# ad-hoc default for agent scratch builds; only `just install` resolves.
resolved_from_keychain=false
if [[ -z "${identity}" ]]; then
  identity="$(find_stored_signing_identity)"
  resolved_from_keychain=true
fi

if [[ "${print_resolved_identity_only}" == "true" ]]; then
  printf '%s\n' "${identity}"
  exit 0
fi

if [[ "${resolved_from_keychain}" == "true" && "${identity}" == "-" ]]; then
  cat >&2 <<'WARNING'
WARNING: signing ad-hoc because the "Bob Mac Capture Local" identity was not
found in the keychain. Notification and Accessibility grants will reset on this
install. See README › Signing to create the stable identity.
WARNING
fi

case "${target_dir}" in
  "~/"*) target_dir="${HOME}/${target_dir#"~/"}" ;;
esac

if [[ "${target_dir}" != "/Applications" && "${target_dir}" != "${HOME}/Applications" ]]; then
  printf 'Refusing to install outside /Applications or ~/Applications: %s\n' "${target_dir}" >&2
  exit 64
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xcode_swift="${package_root}/Scripts/xcode-swift.sh"
bundle_root="${package_root}/.build/install-bundle"
app_name="Bob Mac Capture.app"
staged_app="${bundle_root}/${app_name}"
install_path="${target_dir}/${app_name}"
tmp_path="${target_dir}/.${app_name}.$$"
backup_path="${target_dir}/.${app_name}.previous.$$"

"${package_root}/Scripts/bundle.sh" --identity "${identity}" --output "${bundle_root}" >&2

# The helper is a repository-side tool, not a nested executable in the app bundle.
# Build it with the same release toolchain before touching the installed copy so a
# helper-build failure cannot leave a half-replaced app.
"${xcode_swift}" build --configuration release --product BobMacCaptureInstallHelper >&2
helper_path="$("${xcode_swift}" build --configuration release --show-bin-path)/BobMacCaptureInstallHelper"
if [[ ! -x "${helper_path}" ]]; then
  printf 'Install helper missing: %s\n' "${helper_path}" >&2
  exit 69
fi

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

# Snapshot running instances whose launch-time bundle path is this install_path
# *before* the rename. A running application's reported bundle URL can follow the
# old bundle to backup_path during the swap.
discover_stdout="$("${helper_path}" discover "${install_path}")" || {
  status=$?
  rm -rf "${tmp_path}"
  exit "${status}"
}
discover_pids=()
if [[ -n "${discover_stdout}" ]]; then
  while IFS= read -r pid; do
    if [[ -n "${pid}" ]]; then
      discover_pids+=("${pid}")
    fi
  done <<< "${discover_stdout}"
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

# Restart only after the new copy has verified and the backup is gone. A handoff
# failure must not roll back that verified bundle: the install itself succeeded.
if [[ "${#discover_pids[@]}" -gt 0 ]]; then
  if ! "${helper_path}" restart "${install_path}" "${discover_pids[@]}" >&2; then
    printf 'Installed a verified bundle at %s, but the running-process handoff failed. Start Bob Mac Capture from that path, or use Bob → Restart Bob Mac Capture if an old instance is still running.\n' "${install_path}" >&2
    exit 72
  fi
fi

printf '%s\n' "${install_path}"

#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: Scripts/install.sh [--identity IDENTITY] [--target /Applications|~/Applications]
       [--print-resolved-identity] [--check-signing]

Builds a staged signed app bundle, replaces only the target Bob Mac Capture.app,
verifies the installed bundle identifier and signature, and restarts a copy that
was already running from that exact install path.

--print-resolved-identity prints the signing identity that would be used and
exits without touching anything. Useful for read-only verification on the Mac.

--check-signing checks whether codesign can use the resolved identity without
creating it, building, or installing. It prints the resolved identity on
success. If codesign cannot use it, the command prints fixes and exits 77.
USAGE
}

# Name of the stable self-signed code-signing identity (see README › Signing).
# Signing with it keeps the Accessibility and notification grants across
# reinstalls. The install script creates it when missing from a GUI Terminal.
stable_identity_name="Bob Mac Capture Local"
# The login keychain must be unlocked for codesign to use its private key.
keychain="${HOME}/Library/Keychains/login.keychain-db"
probe_output=""

# find-identity lists identities even when this session cannot use their private keys.
probe_signing_identity() {
  local probe_dir status
  probe_dir="$(/usr/bin/mktemp -d)" || {
    probe_output="Could not create a temporary directory for the signing probe."
    return 1
  }
  if ! /bin/cp /usr/bin/true "${probe_dir}/probe"; then
    probe_output="Could not copy /usr/bin/true for the signing probe."
    /bin/rm -rf "${probe_dir}"
    return 1
  fi
  if probe_output="$(/usr/bin/codesign --force --sign "$1" --timestamp=none "${probe_dir}/probe" 2>&1)"; then
    status=0
  else
    status=$?
  fi
  /bin/rm -rf "${probe_dir}"
  return "${status}"
}

login_keychain_reachable() {
  /usr/bin/security show-keychain-info "${keychain}" >/dev/null 2>&1
}

print_signing_failure_report() {
  local identity="$1" line launchd_manager identity_output found_identity_line=false
  printf 'codesign cannot use the "%s" signing identity from this session:\n' "${identity}" >&2
  if [[ -n "${probe_output}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      printf '    %s\n' "${line}" >&2
    done <<< "${probe_output}"
  else
    printf '    (no codesign diagnostic)\n' >&2
  fi

  if ! login_keychain_reachable; then
    launchd_manager="$(/bin/launchctl managername 2>/dev/null || printf 'unknown')"
    printf 'The login keychain is locked in this session; launchd reports %s (a GUI Terminal reports Aqua).\n' "${launchd_manager}" >&2
    printf 'This happens over SSH and in a tmux server first started over SSH.\n' >&2
    printf 'Nothing was built or installed.\n\n' >&2
    printf 'Fixes:\n' >&2
    printf '  1. Run security unlock-keychain ~/Library/Keychains/login.keychain-db, then rerun from this same shell.\n' >&2
    printf '  2. Rerun from a GUI Terminal window that is not attached to an SSH-started tmux.\n' >&2
    printf '  3. Install ad-hoc with just install ~/Applications -, which resets the Accessibility grant.\n' >&2
    return
  fi

  printf 'codesign was refused the identity private key, or matched more than one identity.\n' >&2
  printf 'Run the install from a GUI Terminal and answer any codesign keychain prompt with Always Allow.\n' >&2
  identity_output="$(/usr/bin/security find-identity -p codesigning 2>/dev/null || true)"
  printf 'Matching security find-identity lines:\n' >&2
  while IFS= read -r line; do
    if [[ "${line}" == *"\"${identity}\""* ]]; then
      printf '    %s\n' "${line}" >&2
      found_identity_line=true
    fi
  done <<< "${identity_output}"
  if [[ "${found_identity_line}" == false ]]; then
    printf '    (none found)\n' >&2
  fi
  printf 'If more than one copy appears, delete the extras in Keychain Access › login › My Certificates and rerun.\n' >&2
}

ensure_signing_identity_usable() {
  local identity="$1"
  if probe_signing_identity "${identity}"; then
    return 0
  fi

  if ! login_keychain_reachable && [[ -t 0 ]]; then
    printf 'The login keychain is locked in this session (SSH, or a tmux server started over SSH), so unlock it to sign with "%s"; macOS asks for the login password.\n' "${identity}" >&2
    /usr/bin/security unlock-keychain "${keychain}" || true
    if probe_signing_identity "${identity}"; then
      return 0
    fi
  fi

  print_signing_failure_report "${identity}"
  exit 77
}

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
check_signing_only=false
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
    --check-signing)
      check_signing_only=true
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

if [[ "${check_signing_only}" == "true" ]]; then
  if [[ "${identity}" != "-" ]]; then
    ensure_signing_identity_usable "${identity}"
  elif [[ "${resolved_from_keychain}" == "true" ]]; then
    printf 'The stable signing identity is missing; just install from a GUI Terminal creates it.\n' >&2
  fi
  printf '%s\n' "${identity}"
  exit 0
fi

if [[ "${resolved_from_keychain}" == "true" && "${identity}" == "-" ]]; then
  if "${package_root}/Scripts/create-signing-identity.sh" >&2; then
    identity="$(find_stored_signing_identity)"
  fi
fi

if [[ "${resolved_from_keychain}" == "true" && "${identity}" == "-" ]]; then
  cat >&2 <<'WARNING'
WARNING: signing ad-hoc because the "Bob Mac Capture Local" identity was not
found in the keychain. The Accessibility grant resets on this install. Run
install again from a GUI Terminal on the Mac to create the identity.
WARNING
fi

case "${target_dir}" in
  \~/*) target_dir="${HOME}/${target_dir#\~/}" ;;
esac

if [[ "${target_dir}" != "/Applications" && "${target_dir}" != "${HOME}/Applications" ]]; then
  printf 'Refusing to install outside /Applications or ~/Applications: %s\n' "${target_dir}" >&2
  exit 64
fi

xcode_swift="${package_root}/Scripts/xcode-swift.sh"
bundle_root="${package_root}/.build/install-bundle"
app_name="Bob Mac Capture.app"
staged_app="${bundle_root}/${app_name}"
install_path="${target_dir}/${app_name}"
tmp_path="${target_dir}/.${app_name}.$$"
backup_path="${target_dir}/.${app_name}.previous.$$"
previous_requirement=""

if [[ "${identity}" != "-" ]]; then
  ensure_signing_identity_usable "${identity}"
fi

designated_requirement() {
  local output line requirement
  output="$(/usr/bin/codesign -d -r- "$1" 2>&1 || true)"
  while IFS= read -r line; do
    if [[ "${line}" == *"designated => "* ]]; then
      requirement="${line#*designated => }"
      requirement="${requirement#\# }"
      printf '%s\n' "${requirement}"
      return 0
    fi
  done <<< "${output}"
  return 0
}

if [[ -e "${install_path}" ]]; then
  previous_requirement="$(designated_requirement "${install_path}")"
fi

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

new_requirement="$(designated_requirement "${install_path}")"
if [[ -n "${previous_requirement}" && -n "${new_requirement}" && "${previous_requirement}" != "${new_requirement}" ]]; then
  if /usr/bin/tccutil reset Accessibility org.bobs.bob-mac-capture >&2; then
    printf 'Cleared the Accessibility grant because the code signature changed. Grant it again from Bob Refs › Tabs › Open Accessibility Settings.\n' >&2
  else
    printf 'The Accessibility grant could not be cleared automatically. Run: tccutil reset Accessibility org.bobs.bob-mac-capture\n' >&2
  fi
fi

# Restart only after the new copy has verified and the backup is gone. A handoff
# failure must not roll back that verified bundle: the install itself succeeded.
if [[ "${#discover_pids[@]}" -gt 0 ]]; then
  if ! "${helper_path}" restart "${install_path}" "${discover_pids[@]}" >&2; then
    printf 'Installed a verified bundle at %s, but the running-process handoff failed. Start Bob Mac Capture from that path, or use Bob → Restart Bob Mac Capture if an old instance is still running.\n' "${install_path}" >&2
    exit 72
  fi
fi

printf '%s\n' "${install_path}"

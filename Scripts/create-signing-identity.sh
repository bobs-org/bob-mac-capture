#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/create-signing-identity.sh

Creates the stable "Bob Mac Capture Local" code-signing identity in the login
keychain. Run from a GUI Terminal on the Mac.
USAGE
}

if [[ $# -gt 0 ]]; then
  case "$1" in
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
fi

name="Bob Mac Capture Local"
keychain="${HOME}/Library/Keychains/login.keychain-db"

# Check this before querying identities: over SSH the login keychain can be
# unreachable, and a security command may otherwise wait for GUI interaction.
if ! /usr/bin/security show-keychain-info "${keychain}" >/dev/null 2>&1; then
  printf 'The login keychain is locked or unreachable. Run this script from a GUI Terminal on the Mac.\n' >&2
  exit 75
fi

identity_output="$(/usr/bin/security find-identity -p codesigning 2>/dev/null || true)"
if [[ "${identity_output}" == *"\"${name}\""* ]]; then
  printf 'The "%s" signing identity already exists in the login keychain.\n' "${name}"
  exit 0
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
config="${work_dir}/certificate.cnf"
key="${work_dir}/private-key.pem"
certificate="${work_dir}/certificate.pem"
p12="${work_dir}/identity.p12"
pass="$(/usr/bin/openssl rand -hex 16)"

cat >"${config}" <<EOF
[req]
distinguished_name = distinguished_name
x509_extensions = extensions
prompt = no

[distinguished_name]
CN = ${name}

[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "${key}" -out "${certificate}" -config "${config}"
/usr/bin/openssl pkcs12 -export -name "${name}" \
  -inkey "${key}" -in "${certificate}" -out "${p12}" \
  -passout "pass:${pass}"
/usr/bin/security import "${p12}" -k "${keychain}" -f pkcs12 \
  -P "${pass}" -T /usr/bin/codesign

identity_output="$(/usr/bin/security find-identity -p codesigning 2>/dev/null || true)"
if [[ "${identity_output}" != *"\"${name}\""* ]]; then
  printf 'The "%s" identity was imported but is still missing from code-signing identities.\n' "${name}" >&2
  exit 1
fi

sha1="$(printf '%s\n' "${identity_output}" | /usr/bin/awk -v needle="\"${name}\"" 'index($0, needle) { sub(/^[[:space:]]*[0-9]+\)[[:space:]]*/, ""); print $1; exit }')"
if [[ -z "${sha1}" ]]; then
  printf 'The "%s" identity is present, but its SHA-1 could not be read.\n' "${name}" >&2
  exit 1
fi
printf 'Created "%s" signing identity (SHA-1: %s).\n' "${name}" "${sha1}"
printf 'The first signed install may show a codesign keychain prompt; choose Always Allow.\n'

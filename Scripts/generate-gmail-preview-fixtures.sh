#!/usr/bin/env bash
# Record realistic Gmail capture-parse spans and dry-run `gmail[]` previews
# from Bob. Peek fixtures stay synthetic: `bob gmail peek` needs Gmail.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-gmail-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-gmail-fixture"
fixtures="$repo_root/Tests/Fixtures"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
cat > "$scratch_root/config.yml" <<'YAML'
relations:
  successor_labels:
    - starts after
YAML

bob() {
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$scratch_root/config.yml" \
    BOB_DIR="$1" \
    BOB_DAY_FILE="$1/day.md" \
    BOB_NOW="2026-11-06 09:30:00" \
    BOB_REF_JOBS_KICK=off \
    TZ="UTC0" \
    "$bob_bin" "${@:2}"
}

persist() {
  python3 - "$1" "$scratch_root" "$stable_root" "$fixtures/$2" <<'PY'
import pathlib
import sys

source, scratch_root, stable_root, destination = sys.argv[1:]
text = pathlib.Path(source).read_text().replace(scratch_root, stable_root)
pathlib.Path(destination).write_text(text)
PY
}

make_vault() {
  local vault="$1"
  mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin"
  cat > "$vault/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'JSON'
{
  "globalFilter": "#task",
  "statusSettings": {
    "coreStatuses": [
      {"symbol":" ","name":"Ready","type":"TODO"},
      {"symbol":"x","name":"Done","type":"DONE"}
    ],
    "customStatuses": [
      {"symbol":"*","name":"Next","type":"TODO"},
      {"symbol":"/","name":"In Progress","type":"IN_PROGRESS"},
      {"symbol":"?","name":"Blocked","type":"TODO"},
      {"symbol":"-","name":"Cancelled","type":"CANCELLED"}
    ]
  }
}
JSON
  cat > "$vault/day.md" <<'EOF'
## Pomodoros

- [ ] Current (0900-0930)
EOF
}

gmail_draft='Follow up https://mail.google.com/mail/u/0/#inbox/FMfcgzQhWTsNRgxMhQNwhZDfgqwXpPsx'

vault="$scratch_root/vault"
make_vault "$vault"

bob "$vault" capture-parse --format json -- "$gmail_draft" > "$scratch_root/parse.json"
persist "$scratch_root/parse.json" "capture-parse-gmail.json"

bob "$vault" capture --dry-run --format json --no-clip -- "$gmail_draft" \
  > "$scratch_root/dry-run.json"
persist "$scratch_root/dry-run.json" "capture-gmail-dry-run.json"

echo "wrote capture-parse-gmail.json capture-gmail-dry-run.json"

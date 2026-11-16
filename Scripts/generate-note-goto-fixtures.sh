#!/usr/bin/env bash
# Generate truthful Go To Notes fixtures from the bob-cli implementation.
# Inputs are written only to an isolated synthetic vault; never use PATH bob.
#
# Synthetic vault inputs:
#   2026/20261114.md (BOB_NOW=2026-11-14 09:00:00)
#   mac_inbox.md with one open #task fixture task
#   Areas/cash.md (area, color green, alias money)
#   Other/money.md (plain note)
#   Views/Monthly.base (Base view; included in Bob's catalog)
#
# Outputs cover capture-parse and capture-complete for `/`, `//`, and `//cash`.
# The note-goto.json alias remains the generated full `//` catalog consumed by
# CaptureCoreTests. Output paths use a stable synthetic root after generation.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (for example bob-cli/target/debug/bob)." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-note-goto-fixtures.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-note-goto-fixture-vault"
vault="$scratch_root/vault"
cache="$scratch_root/cache"
config="$scratch_root/config.yml"
fixtures="$repo_root/Tests/Fixtures"
mkdir -p "$vault/2026" "$vault/Areas" "$vault/Other" "$vault/Views" \
  "$vault/.obsidian/plugins/obsidian-tasks-plugin" "$cache"

cat > "$config" <<'YAML'
plan:
  max_ready_per_note: 5
YAML

cat > "$vault/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'JSON'
{
  "globalFilter": "#task",
  "statusSettings": {
    "coreStatuses": [
      {"symbol":" ","name":"Ready","type":"TODO"},
      {"symbol":"x","name":"Done","type":"DONE"}
    ],
    "customStatuses": [
      {"symbol":"*","name":"Next","type":"ON_HOLD"},
      {"symbol":"/","name":"In Progress","type":"IN_PROGRESS"}
    ]
  }
}
JSON

cat > "$vault/2026/20261114.md" <<'MD'
---
type: "[[day]]"
---
# Saturday
MD

cat > "$vault/mac_inbox.md" <<'MD'
---
type: "[[area]]"
---
# Mac inbox

## Tasks
- [ ] #task Fixture task ^fixture-task
MD

cat > "$vault/Areas/cash.md" <<'MD'
---
type: "[[area]]"
title: cash
aliases: [money]
color: green
---
# Cash
MD

cat > "$vault/Other/money.md" <<'MD'
---
title: Money plan
aliases: [budget]
---
# Money plan
MD

cat > "$vault/Views/Monthly.base" <<'JSON'
{"views":[{"name":"Monthly"}]}
JSON

export BOB_DIR="$vault"
export BOB_CONFIG_FILE="$config"
export BOB_DAY_FILE="$vault/2026/20261114.md"
export BOB_NOW="2026-11-14 09:00:00"
export XDG_CACHE_HOME="$cache"

persist() {
  python3 - "$1" "$fixtures/$2" "$scratch_root" "$stable_root" <<'PY'
import json
import pathlib
import sys

source, destination, scratch_root, stable_root = sys.argv[1:]
raw = pathlib.Path(source).read_text()
for prefix in ("/private" + scratch_root, scratch_root):
    raw = raw.replace(prefix, stable_root)
json.loads(raw)
pathlib.Path(destination).write_text(raw)
PY
}

parse() {
  local draft="$1" out="$2"
  "$bob_bin" capture-parse --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
}

complete() {
  local draft="$1" cursor="$2" out="$3"
  "$bob_bin" capture-complete -b "$vault" --cursor "$cursor" --format json -- \
    "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
}

assert_json() {
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$fixtures/$1"
}

parse "/" note-goto-parse-tasks.json
parse "//" note-goto-parse-notes.json
parse "//cash" note-goto-parse-notes-cash.json
complete "/" 1 note-goto-complete-tasks.json
complete "//" 2 note-goto-complete-notes.json
complete "//" 2 note-goto.json
complete "//cash" 6 note-goto-complete-notes-cash.json
complete "//cash" 2 note-goto-complete-notes-cash-full.json

for fixture in \
  note-goto-parse-tasks.json \
  note-goto-parse-notes.json \
  note-goto-parse-notes-cash.json \
  note-goto-complete-tasks.json \
  note-goto-complete-notes.json \
  note-goto-complete-notes-cash.json \
  note-goto-complete-notes-cash-full.json \
  note-goto.json
do
  assert_json "$fixture"
done

#!/usr/bin/env bash
# Generate truthful complete-label fixtures from this checkout's built Bob.
# Isolated vault, BOB_BIN (not PATH bob), BOB_CONFIG_FILE, XDG_CACHE_HOME.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (e.g. bob-cli's CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
scratch_root="$(mktemp -d /tmp/bob-relation-complete-fixture-vault.XXXXXX)"
cache_home="$(mktemp -d /tmp/bob-relation-complete-cache.XXXXXX)"
trap 'rm -rf -- "$scratch_root" "$cache_home"' EXIT
mkdir -p "$scratch_root/.obsidian/plugins/obsidian-tasks-plugin"
cat > "$scratch_root/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'JSON'
{
  "globalFilter": "#task",
  "taskFormat": "dataview",
  "statusSettings": {
    "coreStatuses": [
      {"symbol":" ","name":"Todo","type":"TODO"},
      {"symbol":"x","name":"Done","type":"DONE"}
    ],
    "customStatuses": [
      {"symbol":"?","name":"Blocked","type":"ON_HOLD"},
      {"symbol":"-","name":"Cancelled","type":"CANCELLED"},
      {"symbol":"/","name":"In Progress","type":"IN_PROGRESS"},
      {"symbol":"*","name":"Next","type":"ON_HOLD"}
    ]
  }
}
JSON
cat > "$scratch_root/design.md" <<'MD'
- [ ] #task Ship retry policy [id:: design__ship] ^ship
- [ ] #task Weekly review 🔁 ^weekly
- [x] #task Old idea ^old
- [-] #task Gone idea ^gone
MD
cat > "$scratch_root/follow.md" <<'MD'
- [?] #task Announce launch [dependsOn:: design__ship] [id:: follow__announce] ^announce
- [?] #task Update changelog [dependsOn:: design__ship] [id:: follow__changelog] ^changelog
MD
cat > "$scratch_root/verify.md" <<'MD'
- [ ] #task Verify cancel labels ^confirm
MD
cat > "$scratch_root/inbox.md" <<'MD'
# Inbox
MD
cat > "$scratch_root/catalog.md" <<'MD'
- [ ] #task First entry ^first
  - 🪢 **LINKS:** implemented by [[verify#^confirm]]
- [ ] #task Second entry ^second
  - 🪢 **LINKS:** verified by [[verify#^confirm]]
- [ ] #task Third entry ^third
  - 🪢 **LINKS:** implemented by [[verify#^confirm]] • verified by [[verify#^confirm]]
- [ ] #task Fourth entry ^fourth
  - 🪢 **LINKS:** implements [[verify#^confirm]]
- [ ] #task Fifth entry ^fifth
  - 🪢 **LINKS:** verifies [[verify#^confirm]]
- [ ] #task Sixth entry ^sixth
  - 🪢 **LINKS:** inspired by [[verify#^confirm]]
MD
cat > "$scratch_root/proj.md" <<'MD'
- [ ] #task Big project ^prj
- [ ] #task Resident one ^r1
- [ ] #task Resident two ^r2
MD
cat > "$scratch_root/today.md" <<'MD'
## Pomodoros
- [ ] (**0920-0950**) — FIX
  - [[follow#^announce]]
MD
config_file="$scratch_root/config.yml"
cat > "$config_file" <<'YAML'
relations:
  complete_labels:
    - implemented by
    - verified by
YAML
export BOB_DIR="$scratch_root"
export BOB_CONFIG_FILE="$config_file"
export BOB_DAY_FILE="$scratch_root/today.md"
export BOB_NOW="2026-10-29"
export XDG_CACHE_HOME="$cache_home"
fixtures="$repo_root/Tests/Fixtures"
complete() {
  local draft="$1"; local out="$2"
  local cursor="${#draft}"
  "$bob_bin" capture-complete --cursor "$cursor" --format json -- "$draft" \
    > "$fixtures/$out"
}
parse() {
  local draft="$1"; local out="$2"
  "$bob_bin" capture-parse --format json -- "$draft" > "$fixtures/$out"
}
capture_json() {
  local draft="$1"; local out="$2"; shift 2
  "$bob_bin" capture --format json "$@" -- "$draft" > "$fixtures/$out"
}
# Opening complete-label complete: typed partial, configured overlay, completes verdict.
complete 'Use this @design+ship ~verify:confirm|impl' relation-complete-complete-impl.json
# Fully typed complete label marks the typed row.
complete 'Use this @design+ship ~verify:confirm|"implemented by"' relation-complete-complete-implemented-by.json
# New-task and recurring sources refuse both configured labels with empty replacements.
complete 'New idea @inbox ~verify:confirm|' relation-complete-complete-new-task.json
complete 'New idea @inbox ~verify:confirm|"implemented by"' relation-complete-complete-new-task-typed.json
complete '@design+ship ~~design:weekly|' relation-complete-complete-recurring.json
# Already-closed source (Done).
complete 'Use this @design+old ~verify:confirm|"implemented by"' relation-complete-complete-already-closed.json
# Inverse hint on a non-complete label.
complete 'Use this @design+ship ~verify:confirm|implements' relation-complete-complete-inverse.json
parse 'Use this @design+ship ~verify:confirm|"implemented by"' relation-complete-parse.json
capture_json 'Close this @design+ship ~verify:confirm|"implemented by"' relation-complete-dry-run.json --dry-run
capture_json 'Close this @design+ship ~verify:confirm|"implemented by"' relation-complete-commit.json -p all
echo "Generated relation-complete fixtures with $($bob_bin --version | head -n 1)"

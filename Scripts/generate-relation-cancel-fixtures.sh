#!/usr/bin/env bash
# Generate truthful cancel-label fixtures from this checkout's built Bob.
# Isolated vault, BOB_BIN (not PATH bob), BOB_CONFIG_FILE, XDG_CACHE_HOME.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (e.g. bob-cli's CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
scratch_root="$(mktemp -d /tmp/bob-relation-cancel-fixture-vault.XXXXXX)"
cache_home="$(mktemp -d /tmp/bob-relation-cancel-cache.XXXXXX)"
trap 'rm -rf -- "$scratch_root" "$cache_home"' EXIT
mkdir -p "$scratch_root/.obsidian/plugins/obsidian-tasks-plugin"
cat > "$scratch_root/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'JSON'
{
  "globalFilter": "#task",
  "statusSettings": {
    "coreStatuses": [
      {"symbol":" ","name":"Todo","type":"TODO"},
      {"symbol":"x","name":"Done","type":"DONE"}
    ],
    "customStatuses": [
      {"symbol":"-","name":"Cancelled","type":"CANCELLED"},
      {"symbol":"/","name":"In Progress","type":"IN_PROGRESS"},
      {"symbol":"*","name":"Next","type":"ON_HOLD"}
    ]
  }
}
JSON
cat > "$scratch_root/cash.md" <<'MD'
- [ ] #task Sell stocks! ^sell
MD
cat > "$scratch_root/invest.md" <<'MD'
- [ ] #task Sell stocks now! ^now
- [ ] #task Weekly review 🔁 ^weekly
- [x] #task Old idea ^old
- [-] #task Gone idea ^gone
MD
cat > "$scratch_root/proj.md" <<'MD'
- [ ] #task Big project ^prj
- [ ] #task Resident one ^r1
- [ ] #task Resident two ^r2
MD
config_file="$scratch_root/config.yml"
cat > "$config_file" <<'YAML'
relations:
  cancel_labels:
    - duplicate of
    - superseded by
YAML
export BOB_DIR="$scratch_root"
export BOB_CONFIG_FILE="$config_file"
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
# Opening cancel-label complete: typed partial, configured overlay, cancels verdict.
complete 'Use this @cash+sell ~invest:now|dup' relation-cancel-complete-dup.json
# Fully typed cancel label marks the typed row.
complete 'Use this @cash+sell ~invest:now|"duplicate of"' relation-cancel-complete-duplicate.json
# Already-closed source (Cancelled).
complete 'Use this @invest+gone ~invest:now|"duplicate of"' relation-cancel-complete-already-closed.json
# Inverse hint on a non-cancel label.
complete 'Use this @cash+sell ~invest:now|supersedes' relation-cancel-complete-inverse.json
parse 'Use this @cash+sell ~invest:now|"duplicate of"' relation-cancel-parse.json
capture_json 'Use this @cash+sell ~invest:now|"duplicate of"' relation-cancel-dry-run.json --dry-run
capture_json 'Use this @cash+sell ~invest:now|"duplicate of"' relation-cancel-commit.json
echo "Generated relation-cancel fixtures with $($bob_bin --version | head -n 1)"

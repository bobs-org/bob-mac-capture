#!/usr/bin/env bash
# Record realistic capture `>` transfer responses and parser spans from Bob.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-transfer-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-transfer-fixture"
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
    BOB_NOW="2026-11-03 09:30:00" \
    BOB_REF_JOBS_KICK=off \
    TZ="UTC0" \
    "$bob_bin" "${@:2}"
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

write_basic_vault() {
  local vault="$1"
  make_vault "$vault"
  mkdir -p "$vault"
  cat > "$vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Benchmark logical replication ^bench
  - Try pgbench at 10k TPS
- [ ] #task Cut over prod ^cutover
EOF
  cat > "$vault/db.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Upgrade Postgres to 17 [priority:: 2] ^upgrade
EOF
  cat > "$vault/referrer.md" <<'EOF'
---
type: "[[area]]"
---
See [[inbox#^bench]] for context.
EOF
  cat > "$vault/day.md" <<'EOF'
## Pomodoros

- [ ] Current (0900-0930)
EOF
}

run_dry() {
  local vault="$1"
  local draft="$2"
  local output="$3"
  bob "$vault" capture --dry-run --format json -- "$draft" > "$output"
}

shot_vault="$scratch_root/screenshot"
make_vault "$shot_vault"
cat > "$shot_vault/work.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [*] #task Add `=<ch>` jumper keymaps (see [[org]])! ^ch-jumper-keymaps
- [*] #task Add `<ctrl+h/l>` capture keymaps to jump to prev/next word! ^capture-ctrl-hl
- [ ] #task Always add capture time to ref marker note! ^always-capture-ref-time
EOF
cat > "$shot_vault/day.md" <<'EOF'
## Pomodoros

- [ ] Current (0900-0930)
EOF
run_dry "$shot_vault" \
  '@work+ch-jumper-keymaps @work+capture-ctrl-hl > @work+always-capture-ref-time' \
  "$scratch_root/screenshot-merge.json"

consequence_vault="$scratch_root/consequences"
make_vault "$consequence_vault"
cat > "$consequence_vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Benchmark logical replication ^bench
- [ ] #task Measure failover window ^measure
  - ⛓️ **DEPENDS ON:** [[db#^prerequisite]]
EOF
cat > "$consequence_vault/db.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Upgrade Postgres to 17 ^upgrade
- [ ] #task Prepare test environment ^prerequisite
EOF
cat > "$consequence_vault/dependents.md" <<'EOF'
---
type: "[[area]]"
---
- [ ] #task Cut over prod ^cutover
  - ⛓️ **DEPENDS ON:** [[inbox#^bench]]
EOF
cat > "$consequence_vault/successors.md" <<'EOF'
---
type: "[[area]]"
---
- [ ] #task Deploy the upgrade ^deploy
  - 🪢 **LINKS:** starts after [[inbox#^bench]]
EOF
cat > "$consequence_vault/day.md" <<'EOF'
## Pomodoros

- [ ] (0900-0930) — BUILD
  - [[inbox#^bench]]
- [ ] (0930-1000) — TEST
  - [[inbox#^measure]]
EOF
run_dry "$consequence_vault" \
  '@inbox+bench @inbox+measure > @db+upgrade' \
  "$scratch_root/consequences-offers.json"

drawer_vault="$scratch_root/drawer"
write_basic_vault "$drawer_vault"
run_dry "$drawer_vault" '@inbox+bench > @db+upgrade#future-work' \
  "$scratch_root/drawer-merge.json"

section_vault="$scratch_root/section"
write_basic_vault "$section_vault"
run_dry "$section_vault" '@inbox+bench > @db#future-work' \
  "$scratch_root/section-merge.json"

move_vault="$scratch_root/move"
write_basic_vault "$move_vault"
cat >> "$move_vault/inbox.md" <<'EOF'
- [ ] #task Analyze replica lag ^replica-lag
EOF
run_dry "$move_vault" '@inbox+bench @inbox+replica-lag > @db' \
  "$scratch_root/move.json"

unchanged_vault="$scratch_root/unchanged"
write_basic_vault "$unchanged_vault"
merge_draft='@inbox+bench > @db+upgrade'
bob "$unchanged_vault" capture --format json -- "$merge_draft" \
  > "$scratch_root/unchanged-commit.json"
run_dry "$unchanged_vault" "$merge_draft" "$scratch_root/unchanged-rerun.json"

parse_vault="$scratch_root/parse"
write_basic_vault "$parse_vault"
bob "$parse_vault" capture-parse --format json -- '@inbox+bench > @db' \
  > "$scratch_root/parse-move.json"
bob "$parse_vault" capture-parse --format json -- \
  '@work+ch-jumper-keymaps > @work+always-capture-ref-time' \
  > "$scratch_root/parse-merge.json"
bob "$parse_vault" capture-parse --format json -- '@inbox+bench > @' \
  > "$scratch_root/parse-incomplete.json"

python3 - "$scratch_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
def load(name):
    return json.loads((root / name).read_text())

shot = load("screenshot-merge.json")
effects = load("consequences-offers.json")
drawer = load("drawer-merge.json")
section = load("section-merge.json")
move = load("move.json")
unchanged = load("unchanged-rerun.json")
parse_move = load("parse-move.json")
parse_merge = load("parse-merge.json")
parse_incomplete = load("parse-incomplete.json")

assert shot.get("kind") == "task_merge" and len(shot.get("merges", [])) == 2, shot
assert "[[org]]" in shot["merges"][0]["source"]["title"], shot
assert "`=<ch>`" in shot["merges"][0]["source"]["title"], shot

records = effects.get("merges", [])
assert effects.get("kind") == "task_merge" and len(records) == 2, effects
assert all(record.get("previous_status_name") == "Ready" for record in records), records
assert all(record.get("status_name") == "Cancelled" for record in records), records
assert all(record.get("target", {}).get("line") for record in records), records
assert all("created" in record.get("target", {}) for record in records), records
assert any(record.get("consequences") for record in records), records
assert any(
    row.get("kind") == "dependent" and "Cut over prod" in row.get("text", "")
    for record in records for row in record.get("consequences", [])
), records
assert any(
    row.get("kind") == "prerequisite_left" for record in records
    for row in record.get("consequences", [])
), records
assert any(
    row.get("kind") == "successor_orphaned" for record in records
    for row in record.get("consequences", [])
), records
assert len(effects.get("merge_offers", [])) >= 1, effects
assert all(row.get("trigger") == "merge" for row in effects["merge_offers"]), effects

assert drawer.get("kind") == "task_merge" and drawer["merges"][0]["target"]["created"] is True, drawer
assert section.get("kind") == "task_merge" and section["merges"][0]["target"]["created"] is True, section
assert section["merges"][0]["target"].get("section") == "Future Work", section

assert move.get("kind") == "task_move" and len(move.get("moves", [])) == 2, move
assert all(row.get("destination_line") and row.get("destination_section") == "Tasks" for row in move["moves"]), move
assert all(row.get("status_name") == "Ready" for row in move["moves"]), move
assert unchanged.get("kind") == "task_merge", unchanged
assert all(row.get("outcome") == "unchanged" for row in unchanged.get("merges", [])), unchanged

assert parse_move.get("mode") == "task_move", parse_move
assert parse_merge.get("mode") == "task_merge", parse_merge
assert "transfer_destination" in parse_incomplete.get("needs", []), parse_incomplete
for parsed in (parse_move, parse_merge):
    kinds = {span["kind"] for span in parsed.get("spans", [])}
    assert {"transfer_source", "transfer_arrow", "transfer_destination"} <= kinds, parsed
PY

persist "$scratch_root/screenshot-merge.json" capture-transfer-merge.json
persist "$scratch_root/consequences-offers.json" capture-transfer-consequences-offers.json
persist "$scratch_root/drawer-merge.json" capture-transfer-drawer-merge.json
persist "$scratch_root/section-merge.json" capture-transfer-section-merge.json
persist "$scratch_root/move.json" capture-transfer-move.json
persist "$scratch_root/unchanged-rerun.json" capture-transfer-unchanged-merge.json
persist "$scratch_root/parse-move.json" capture-parse-transfer-move.json
persist "$scratch_root/parse-merge.json" capture-parse-transfer-merge.json
persist "$scratch_root/parse-incomplete.json" capture-parse-transfer-incomplete.json
echo "wrote capture transfer fixtures to $fixtures"

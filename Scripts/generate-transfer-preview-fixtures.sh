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

run_failure() {
  local vault="$1"
  local draft="$2"
  local output="$3"
  local expected_code="$4"
  local exit_code
  set +e
  bob "$vault" capture --dry-run --format json -- "$draft" > "$output"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    echo "expected $expected_code for: $draft" >&2
    exit 1
  fi
  python3 - "$output" "$expected_code" <<'PY'
import json
import pathlib
import sys

path, expected = sys.argv[1:]
response = json.loads(pathlib.Path(path).read_text())
assert response.get("ok") is False, response
assert response.get("code") == expected, response
PY
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

tombstone_vault="$scratch_root/tombstone"
write_basic_vault "$tombstone_vault"
python3 - "$tombstone_vault/inbox.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = "  - Try pgbench at 10k TPS\n"
assert needle in text
path.write_text(text.replace(
    needle,
    needle + "  - Check replica lag\n  - Capture failover time\n",
    1,
))
PY
run_dry "$tombstone_vault" '@inbox+bench > @db+upgrade' \
  "$scratch_root/tombstone-merge.json"

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
bob "$parse_vault" capture-parse --format json -- '@inbox+bench > @db+' \
  > "$scratch_root/parse-pending-block-id.json"
bob "$parse_vault" capture-parse --format json -- '@inbox+bench > @db#' \
  > "$scratch_root/parse-pending-section.json"
bob "$parse_vault" capture-parse --format json -- '@inbox+bench > @db+upgrade#' \
  > "$scratch_root/parse-pending-drawer.json"

pending_vault="$scratch_root/pending"
write_basic_vault "$pending_vault"
run_failure "$pending_vault" '@inbox+bench > ' \
  "$scratch_root/pending-destination.json" incomplete_transfer
run_failure "$pending_vault" '@inbox+bench > @db+' \
  "$scratch_root/pending-block-id.json" incomplete_transfer_block_id
run_failure "$pending_vault" '@inbox+bench > @db#' \
  "$scratch_root/pending-section.json" incomplete_transfer_section
run_failure "$pending_vault" '@inbox+bench > @db+upgrade#' \
  "$scratch_root/pending-drawer.json" incomplete_transfer_drawer
run_failure "$pending_vault" '@inbox+bnch > ' \
  "$scratch_root/pending-typo-source.json" incomplete_transfer

refusal_vault="$scratch_root/refusal"
write_basic_vault "$refusal_vault"
cat > "$refusal_vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Benchmark logical replication ^bench
  - [ ] #task Add a load test ^bench-sub
EOF
run_failure "$refusal_vault" '@inbox+bench > @db+upgrade' \
  "$scratch_root/refusal-open-subtasks.json" merge_source_open_subtasks
run_failure "$pending_vault" '@inbox+bench > @db extra' \
  "$scratch_root/refusal-extra-text.json" transfer_extra_text

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
tombstone = load("tombstone-merge.json")
move = load("move.json")
unchanged = load("unchanged-rerun.json")
parse_move = load("parse-move.json")
parse_merge = load("parse-merge.json")
parse_incomplete = load("parse-incomplete.json")
parse_pending_block_id = load("parse-pending-block-id.json")
parse_pending_section = load("parse-pending-section.json")
parse_pending_drawer = load("parse-pending-drawer.json")
pending_destination = load("pending-destination.json")
pending_block_id = load("pending-block-id.json")
pending_section = load("pending-section.json")
pending_drawer = load("pending-drawer.json")
pending_typo = load("pending-typo-source.json")
refusal_open_subtasks = load("refusal-open-subtasks.json")
refusal_extra_text = load("refusal-extra-text.json")

assert shot.get("kind") == "task_merge" and len(shot.get("merges", [])) == 2, shot
assert "[[org]]" in shot["merges"][0]["source"]["title"], shot
assert "`=<ch>`" in shot["merges"][0]["source"]["title"], shot
shot_roles = [role for block in shot.get("task_blocks", []) for role in block.get("roles", [])]
assert "merge_target" in shot_roles and shot_roles.count("merge_source") == 2, shot

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
assert any(
    "merge_target" in block.get("roles", []) for block in drawer.get("task_blocks", [])
), drawer
assert section.get("kind") == "task_merge" and section["merges"][0]["target"]["created"] is True, section
assert section["merges"][0]["target"].get("section") == "Future Work", section
section_blocks = section.get("section_blocks", [])
assert len(section_blocks) == 1 and section_blocks[0].get("heading") == "Future Work", section
assert section_blocks[0].get("created") is True, section_blocks
assert section_blocks[0].get("roles") == ["merge_target"], section_blocks
assert section_blocks[0].get("lines", [])[0].get("text") == "## Future Work", section_blocks
assert tombstone.get("kind") == "task_merge", tombstone
assert any(
    "merge_source" in block.get("roles", [])
    and any(line.get("change") == "removed" for line in block.get("lines", []))
    for block in tombstone.get("task_blocks", [])
), tombstone

assert move.get("kind") == "task_move" and len(move.get("moves", [])) == 2, move
assert all(row.get("destination_line") and row.get("destination_section") == "Tasks" for row in move["moves"]), move
assert all(row.get("status_name") == "Ready" for row in move["moves"]), move
move_blocks = [block for block in move.get("task_blocks", []) if "moved" in block.get("roles", [])]
assert len(move_blocks) == 2, move
assert all(block.get("moved_from", {}).get("relative_target") == "inbox.md" for block in move_blocks), move
assert move_blocks[0]["moved_from"]["line"] == 5, move_blocks
assert all(block["moved_from"]["line"] > 0 for block in move_blocks), move_blocks
assert unchanged.get("kind") == "task_merge", unchanged
assert all(row.get("outcome") == "unchanged" for row in unchanged.get("merges", [])), unchanged
assert not any(
    role in {"merge_target", "merge_source", "moved"}
    for block in unchanged.get("task_blocks", []) for role in block.get("roles", [])
), unchanged
assert not unchanged.get("section_blocks"), unchanged

assert parse_move.get("mode") == "task_move", parse_move
assert parse_merge.get("mode") == "task_merge", parse_merge
assert "transfer_destination" in parse_incomplete.get("needs", []), parse_incomplete
assert "block_id" in parse_pending_block_id.get("needs", []), parse_pending_block_id
assert "section" in parse_pending_section.get("needs", []), parse_pending_section
assert "drawer" in parse_pending_drawer.get("needs", []), parse_pending_drawer
for response, need in [
    (pending_destination, "transfer_destination"),
    (pending_block_id, "block_id"),
    (pending_section, "section"),
    (pending_drawer, "drawer"),
]:
    pending = response.get("transfer_pending")
    assert pending and pending.get("need") == need, response
    assert len(pending.get("sources", [])) == 1, response
    assert len(pending.get("forms", [])) == 4, response
assert not any(row.get("active") for row in pending_destination["transfer_pending"]["forms"]), pending_destination
assert next(row for row in pending_block_id["transfer_pending"]["forms"] if row["form"] == "@note+task")["active"], pending_block_id
assert next(row for row in pending_section["transfer_pending"]["forms"] if row["form"] == "@note#section")["active"], pending_section
assert next(row for row in pending_drawer["transfer_pending"]["forms"] if row["form"] == "@note+task#drawer")["active"], pending_drawer
assert pending_typo["transfer_pending"]["sources"][0]["error"]["code"] == "missing_task", pending_typo
assert refusal_open_subtasks.get("code") == "merge_source_open_subtasks", refusal_open_subtasks
assert refusal_extra_text.get("code") == "transfer_extra_text", refusal_extra_text
for parsed in (parse_move, parse_merge):
    kinds = {span["kind"] for span in parsed.get("spans", [])}
    assert {"transfer_source", "transfer_arrow", "transfer_destination"} <= kinds, parsed
PY

persist "$scratch_root/screenshot-merge.json" capture-transfer-merge.json
persist "$scratch_root/consequences-offers.json" capture-transfer-consequences-offers.json
persist "$scratch_root/drawer-merge.json" capture-transfer-drawer-merge.json
persist "$scratch_root/section-merge.json" capture-transfer-section-merge.json
persist "$scratch_root/tombstone-merge.json" capture-transfer-tombstone-merge.json
persist "$scratch_root/move.json" capture-transfer-move.json
persist "$scratch_root/unchanged-rerun.json" capture-transfer-unchanged-merge.json
persist "$scratch_root/parse-move.json" capture-parse-transfer-move.json
persist "$scratch_root/parse-merge.json" capture-parse-transfer-merge.json
persist "$scratch_root/parse-incomplete.json" capture-parse-transfer-incomplete.json
persist "$scratch_root/parse-pending-block-id.json" capture-parse-transfer-pending-block-id.json
persist "$scratch_root/parse-pending-section.json" capture-parse-transfer-pending-section.json
persist "$scratch_root/parse-pending-drawer.json" capture-parse-transfer-pending-drawer.json
persist "$scratch_root/pending-destination.json" capture-transfer-pending-destination.json
persist "$scratch_root/pending-block-id.json" capture-transfer-pending-block-id.json
persist "$scratch_root/pending-section.json" capture-transfer-pending-section.json
persist "$scratch_root/pending-drawer.json" capture-transfer-pending-drawer.json
persist "$scratch_root/pending-typo-source.json" capture-transfer-pending-typo-source.json
persist "$scratch_root/refusal-open-subtasks.json" capture-transfer-refusal-open-subtasks.json
persist "$scratch_root/refusal-extra-text.json" capture-transfer-refusal-extra-text.json
echo "wrote capture transfer fixtures to $fixtures"

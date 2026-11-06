#!/usr/bin/env bash
# Record realistic capture `<` merge-in responses and parser spans from Bob.
# Follows Scripts/generate-transfer-preview-fixtures.sh: deterministic output
# from an explicit BOB_BIN with isolated configuration, a fixed clock, and
# disposable vaults. Generated paths are stabilized so fixtures stay portable.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi

bob_commit="${BOB_COMMIT:-}"
if [[ -z "$bob_commit" ]]; then
  bob_commit="$("$bob_bin" --version 2>/dev/null || echo unknown)"
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-merge-in-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-merge-in-fixture"
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

bob_with_config() {
  local config="$1"
  local vault="$2"
  shift 2
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$config" \
    BOB_DIR="$vault" \
    BOB_DAY_FILE="$vault/day.md" \
    BOB_NOW="2026-11-03 09:30:00" \
    BOB_REF_JOBS_KICK=off \
    TZ="UTC0" \
    "$bob_bin" "$@"
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
- [ ] #task Alpha task ^aaa
  - Alpha detail note
- [ ] #task Beta task ^bbb
  - Beta detail note
  - Second beta note
- [ ] #task Gamma task ^ccc
- [ ] #task Delta task ^ddd
- [ ] #task Epsilon task ^eee
EOF
  cat > "$vault/db.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Upgrade Postgres to 17 ^upgrade
EOF
  cat > "$vault/day.md" <<'EOF'
## Pomodoros

- [ ] Current (0900-0930)
EOF
}

write_rich_vault() {
  local vault="$1"
  write_basic_vault "$vault"
  cat > "$vault/dependents.md" <<'EOF'
---
type: "[[area]]"
---
- [ ] #task Cut over prod ^cutover
  - ⛓️ **DEPENDS ON:** [[inbox#^aaa]]
EOF
  cat >> "$vault/day.md" <<'EOF'
  - [[inbox#^aaa]]
EOF
  cat > "$vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Alpha task ^aaa
  - Alpha detail note
- [ ] #task Beta task ^bbb
  - Beta detail note
  - Second beta note
- [ ] #task Gamma task ^ccc
- [ ] #task Delta task ^ddd
- [ ] #task Epsilon task ^eee
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

parse_vault="$scratch_root/parse"
write_basic_vault "$parse_vault"
bob "$parse_vault" capture-parse --format json -- 'New outcome < @inbox+aaa' \
  > "$scratch_root/parse-one.json"
bob "$parse_vault" capture-parse --format json -- 'New outcome < @inbox+aaa @inbox+bbb' \
  > "$scratch_root/parse-two.json"
bob "$parse_vault" capture-parse --format json -- \
  'New outcome < @inbox+aaa @inbox+bbb @inbox+ccc @inbox+ddd @inbox+eee' \
  > "$scratch_root/parse-five.json"
bob "$parse_vault" capture-parse --format json -- 'New outcome <' \
  > "$scratch_root/parse-pending-terminal.json"
bob "$parse_vault" capture-parse --format json -- 'New outcome < @inbox+aaa @inbox+' \
  > "$scratch_root/parse-pending-second.json"
bob "$parse_vault" capture-parse --format json -- 'New outcome < +' \
  > "$scratch_root/parse-pending-plus.json"
bob "$parse_vault" capture-parse --format json -- 'text<@inbox+aaa' \
  > "$scratch_root/parse-rewrite-spacing.json"
bob "$parse_vault" capture-parse --format json -- 'New outcome < @inbox+aaa s:3' \
  > "$scratch_root/parse-rewrite-extra.json"
bob "$parse_vault" capture-parse --format json -- '@inbox+aaa < @inbox+bbb' \
  > "$scratch_root/parse-rewrite-needs-new-task.json"
bob "$parse_vault" capture-parse --format json -- 'New outcome < @inbox+aaa @inbox+aaa' \
  > "$scratch_root/parse-refusal-duplicate.json"
bob "$parse_vault" capture-parse --format json -- 'Tâche ünïcodé café < @inbox+aaa' \
  > "$scratch_root/parse-unicode.json"
bob "$parse_vault" capture-parse --format json -- 'First < @inbox+aaa

Second plain' \
  > "$scratch_root/parse-bulk-mixed.json"

success_vault="$scratch_root/success"
write_rich_vault "$success_vault"
title_only_vault="$scratch_root/title-only"
make_vault "$title_only_vault"
cat > "$title_only_vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Bare source ^bare
- [ ] #task Other source ^other
EOF
cat > "$title_only_vault/db.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Upgrade Postgres ^upgrade
EOF
cat > "$title_only_vault/day.md" <<'EOF'
## Pomodoros

- [ ] Current (0900-0930)
EOF
run_dry "$title_only_vault" 'New outcome < @inbox+bare' \
  "$scratch_root/complete-one.json"
run_dry "$success_vault" 'New outcome < @inbox+aaa @inbox+bbb' \
  "$scratch_root/complete-two.json"
run_dry "$success_vault" \
  'New outcome < @inbox+aaa @inbox+bbb @inbox+ccc @inbox+ddd @inbox+eee' \
  "$scratch_root/complete-five.json"

dup_vault="$scratch_root/duplicate"
write_basic_vault "$dup_vault"
cat > "$dup_vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Repeated title ^rep1
- [ ] #task Repeated title ^rep2
- [ ] #task Beta task ^bbb
EOF
run_dry "$dup_vault" 'New outcome < @inbox+rep1 @inbox+rep2' \
  "$scratch_root/complete-duplicate-titles.json"

long_vault="$scratch_root/long"
write_basic_vault "$long_vault"
cat > "$long_vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task This is an exceptionally long task title that keeps going well past one hundred characters to stress wrapping and disclosure copy ^long1
  - A note that moved along
- [ ] #task Beta task ^bbb
EOF
run_dry "$long_vault" 'New outcome < @inbox+long1 @inbox+bbb' \
  "$scratch_root/complete-long-title.json"

unicode_vault="$scratch_root/unicode"
write_basic_vault "$unicode_vault"
cat > "$unicode_vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Tâche ünïcodé café ☕ ^uni1
  - détail ünïcodé
- [ ] #task Beta task ^bbb
EOF
run_dry "$unicode_vault" 'Tâche ünïcodé < @inbox+uni1' \
  "$scratch_root/complete-unicode.json"
run_dry "$title_only_vault" 'Second outcome < @inbox+other' \
  "$scratch_root/complete-title-only.json"

blocked_vault="$scratch_root/blocked"
write_rich_vault "$blocked_vault"
run_dry "$blocked_vault" 'New target @inbox^target s:3 < @inbox+aaa' \
  "$scratch_root/complete-blocked-target.json"

list_vault="$scratch_root/list"
write_basic_vault "$list_vault"
bob "$list_vault" capture --dry-run --format json -- '@inbox
- First target < @inbox+aaa
- Second target < @inbox+bbb' > "$scratch_root/complete-task-list.json"

label_vault="$scratch_root/label"
write_basic_vault "$label_vault"
cat > "$label_vault/label-config.yml" <<'YAML'
relations:
  merge_labels:
    - merged into
YAML
bob_with_config "$label_vault/label-config.yml" "$label_vault" capture --dry-run \
  --format json -- 'New outcome < @inbox+aaa' > "$scratch_root/complete-label.json"

transfer_origin_vault="$scratch_root/transfer-origin"
write_basic_vault "$transfer_origin_vault"
run_dry "$transfer_origin_vault" '@inbox+bbb > @db+upgrade' \
  "$scratch_root/transfer-origin.json"

pending_vault="$scratch_root/pending"
write_basic_vault "$pending_vault"
run_failure "$pending_vault" 'New outcome < @inbox+aaa @inbox+' \
  "$scratch_root/pending-second.json" incomplete_merge_in
run_failure "$pending_vault" 'New outcome < @inbox+typo @inbox+' \
  "$scratch_root/pending-error.json" incomplete_merge_in

closed_vault="$scratch_root/closed"
write_basic_vault "$closed_vault"
python3 - "$closed_vault/inbox.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "- [ ] #task Alpha task ^aaa",
    "- [x] #task Alpha task ^aaa",
    1,
)
path.write_text(text)
PY
run_failure "$closed_vault" 'New outcome < @inbox+aaa @inbox+' \
  "$scratch_root/pending-unmergeable.json" incomplete_merge_in

refusal_vault="$scratch_root/refusal"
write_basic_vault "$refusal_vault"
run_failure "$refusal_vault" 'New outcome < @inbox+aaa @inbox+aaa' \
  "$scratch_root/refusal-duplicate.json" duplicate_capture_target
run_failure "$refusal_vault" 'New outcome < @inbox+zzz' \
  "$scratch_root/refusal-missing.json" task_not_found
run_failure "$refusal_vault" 'New target @inbox &inbox:aaa < @inbox+aaa' \
  "$scratch_root/refusal-also-marked.json" merge_in_source_also_marked

complete_vault="$scratch_root/complete-slot"
write_basic_vault "$complete_vault"
bob "$complete_vault" capture-complete --cursor 15 --format json -- 'New outcome < +' \
  > "$scratch_root/complete-slot.json"

related_vault="$scratch_root/related"
write_basic_vault "$related_vault"
bob "$related_vault" capture-related --format json -- 'New outcome < @inbox+aaa' \
  > "$scratch_root/related.json"

python3 - "$scratch_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
def load(name):
    return json.loads((root / name).read_text())

one = load("parse-one.json")
assert one.get("mode") == "task", one
assert one.get("grammar") == 15, one
assert one["merge_in"]["arrow"] == {"start": 12, "end": 13}, one
assert [s["marker"] for s in one["merge_in"]["sources"]] == ["@inbox+aaa"], one
assert [s["kind"] for s in one["spans"]] == ["merge_in_arrow", "merge_in_source"], one
assert "items" not in one, one

two = load("parse-two.json")
assert len(two["merge_in"]["sources"]) == 2, two
assert two["merge_in"]["sources"][1]["block_id"] == "bbb", two
assert "items" not in two, two

five = load("parse-five.json")
assert len(five["merge_in"]["sources"]) == 5, five
assert [s["route"] for s in five["merge_in"]["sources"]] == ["inbox"] * 5, five
assert "items" not in five, five

terminal = load("parse-pending-terminal.json")
assert "merge_in_source" in terminal.get("needs", []), terminal
assert terminal["merge_in"] == {"arrow": {"start": 12, "end": 13}, "sources": []}, terminal
assert any(s["kind"] == "interactive_placeholder" for s in terminal["spans"]), terminal

second = load("parse-pending-second.json")
assert "merge_in_source" in second.get("needs", []), second
assert len(second["merge_in"]["sources"]) == 1, second

plus = load("parse-pending-plus.json")
assert "merge_in_source" in plus.get("needs", []), plus
assert plus["merge_in"]["sources"] == [], plus

spacing = load("parse-rewrite-spacing.json")
rewrite = next(d for d in spacing["diagnostics"] if d["code"] == "merge_in_arrow_spacing")
assert rewrite["rewrite"] == {
    "start": 0, "end": 15,
    "replacement": "text < @inbox+aaa", "label": "Add spaces",
}, spacing

extra = load("parse-rewrite-extra.json")
rewrite = next(d for d in extra["diagnostics"] if d["code"] == "merge_in_extra_text")
assert rewrite["rewrite"]["label"] == "Move before <", extra
assert rewrite["rewrite"]["start"] == 0, extra

needs_task = load("parse-rewrite-needs-new-task.json")
rewrite = next(
    d for d in needs_task["diagnostics"] if d["code"] == "merge_in_needs_new_task"
)
assert rewrite["rewrite"] == {
    "start": 0, "end": 23,
    "replacement": "@inbox+bbb > @inbox+aaa", "label": "Use >",
}, needs_task

duplicate_parse = load("parse-refusal-duplicate.json")
assert any(d["code"] == "duplicate_capture_target" for d in duplicate_parse["diagnostics"]), duplicate_parse

bulk = load("parse-bulk-mixed.json")
assert len(bulk["items"]) == 2, bulk
assert bulk["items"][0]["merge_in"]["sources"][0]["marker"] == "@inbox+aaa", bulk
assert "merge_in" not in bulk["items"][1], bulk
assert bulk["merge_in"]["sources"][0]["marker"] == "@inbox+aaa", bulk

single = load("complete-one.json")
assert single.get("kind") == "task", single
assert len(single.get("merges", [])) == 1, single
assert single["merges"][0]["target"]["created"] is True, single
assert single["merges"][0]["message"].endswith("title only"), single
assert single["merges"][0]["source"]["title"] == "Bare source", single
origins = [
    line.get("origin")
    for block in single.get("task_blocks", [])
    for line in block.get("lines", [])
    if "origin" in line
]
assert origins == ["inbox.md#^bare"], single
assert any("merge_target" in block.get("roles", []) for block in single["task_blocks"]), single

pair = load("complete-two.json")
assert len(pair.get("merges", [])) == 2, pair
assert all(m["target"]["created"] is True for m in pair["merges"]), pair
assert any(m.get("consequences") for m in pair["merges"]), pair
assert all("created" in m["target"] for m in pair["merges"]), pair

quint = load("complete-five.json")
assert len(quint.get("merges", [])) == 5, quint

dup = load("complete-duplicate-titles.json")
titles = [m["source"]["title"] for m in dup["merges"]]
assert titles == ["Repeated title", "Repeated title"], dup
assert dup["merges"][0]["source"]["block_id"] != dup["merges"][1]["source"]["block_id"], dup

long = load("complete-long-title.json")
assert len(long["merges"][0]["source"]["title"]) > 100, long

uni = load("complete-unicode.json")
assert "Tâche ünïcodé" in uni["merges"][0]["source"]["title"], uni

title_only = load("complete-title-only.json")
assert title_only["merges"][0]["message"].endswith("title only"), title_only

blocked = load("complete-blocked-target.json")
assert blocked.get("kind") == "task", blocked
assert blocked["merges"][0].get("offers", []) == [], blocked

task_list = load("complete-task-list.json")
assert len(task_list.get("captures", [])) == 2, task_list
assert all(c.get("kind") == "task" for c in task_list["captures"]), task_list

label = load("complete-label.json")
assert len(label.get("merges", [])) == 1, label

transfer_origin = load("transfer-origin.json")
transfer_origins = [
    line.get("origin")
    for block in transfer_origin.get("task_blocks", [])
    for line in block.get("lines", [])
    if "origin" in line
]
assert transfer_origins, transfer_origin
assert set(transfer_origins) == {"inbox.md#^bbb"}, transfer_origin

pending_second = load("pending-second.json")
assert pending_second.get("code") == "incomplete_merge_in", pending_second
pending = pending_second["merge_in_pending"]
assert pending["item"] == 1 and pending["need"] == "merge_in_source", pending_second
assert pending["sources"][0]["mergeable"] is True, pending_second
assert pending["sources"][0]["path"] == "inbox.md", pending_second

pending_error = load("pending-error.json")
assert pending_error["merge_in_pending"]["sources"][0]["error"]["code"], pending_error

pending_unmergeable = load("pending-unmergeable.json")
assert pending_unmergeable["merge_in_pending"]["sources"][0]["mergeable"] is False, pending_unmergeable
assert pending_unmergeable["merge_in_pending"]["sources"][0]["mergeable_code"] == "merge_source_closed", pending_unmergeable

refusal_duplicate = load("refusal-duplicate.json")
assert refusal_duplicate.get("code") == "duplicate_capture_target", refusal_duplicate

refusal_missing = load("refusal-missing.json")
assert refusal_missing.get("code") == "task_not_found", refusal_missing
assert "merge_in_pending" not in refusal_missing, refusal_missing

also_marked = load("refusal-also-marked.json")
assert also_marked.get("code") == "merge_in_source_also_marked", also_marked

slot = load("complete-slot.json")
assert slot.get("context") == "task_parent", slot
assert any("merge in" in (row.get("detail") or "") for row in slot.get("candidates", [])), slot

related = load("related.json")
assert related["items"][0]["linked"] == [{"key": "inbox.md#aaa", "link": "merge_in"}], related
assert related["items"][0]["matches"] == [], related
PY

persist "$scratch_root/parse-one.json" capture-merge-in-parse-one.json
persist "$scratch_root/parse-two.json" capture-merge-in-parse-two.json
persist "$scratch_root/parse-five.json" capture-merge-in-parse-five.json
persist "$scratch_root/parse-pending-terminal.json" capture-merge-in-parse-pending-terminal.json
persist "$scratch_root/parse-pending-second.json" capture-merge-in-parse-pending-second.json
persist "$scratch_root/parse-pending-plus.json" capture-merge-in-parse-pending-plus.json
persist "$scratch_root/parse-rewrite-spacing.json" capture-merge-in-parse-rewrite-spacing.json
persist "$scratch_root/parse-rewrite-extra.json" capture-merge-in-parse-rewrite-extra.json
persist "$scratch_root/parse-rewrite-needs-new-task.json" capture-merge-in-parse-rewrite-needs-new-task.json
persist "$scratch_root/parse-refusal-duplicate.json" capture-merge-in-parse-refusal-duplicate.json
persist "$scratch_root/parse-unicode.json" capture-merge-in-parse-unicode.json
persist "$scratch_root/parse-bulk-mixed.json" capture-merge-in-parse-bulk-mixed.json
persist "$scratch_root/complete-one.json" capture-merge-in-complete-one.json
persist "$scratch_root/complete-two.json" capture-merge-in-complete-two.json
persist "$scratch_root/complete-five.json" capture-merge-in-complete-five.json
persist "$scratch_root/complete-duplicate-titles.json" capture-merge-in-complete-duplicate-titles.json
persist "$scratch_root/complete-long-title.json" capture-merge-in-complete-long-title.json
persist "$scratch_root/complete-unicode.json" capture-merge-in-complete-unicode.json
persist "$scratch_root/complete-title-only.json" capture-merge-in-complete-title-only.json
persist "$scratch_root/complete-blocked-target.json" capture-merge-in-complete-blocked-target.json
persist "$scratch_root/complete-task-list.json" capture-merge-in-complete-task-list.json
persist "$scratch_root/complete-label.json" capture-merge-in-complete-label.json
persist "$scratch_root/transfer-origin.json" capture-merge-in-transfer-origin.json
persist "$scratch_root/pending-second.json" capture-merge-in-pending-second.json
persist "$scratch_root/pending-error.json" capture-merge-in-pending-error.json
persist "$scratch_root/pending-unmergeable.json" capture-merge-in-pending-unmergeable.json
persist "$scratch_root/refusal-duplicate.json" capture-merge-in-refusal-duplicate.json
persist "$scratch_root/refusal-missing.json" capture-merge-in-refusal-missing.json
persist "$scratch_root/refusal-also-marked.json" capture-merge-in-refusal-also-marked.json
persist "$scratch_root/complete-slot.json" capture-merge-in-complete-slot.json
persist "$scratch_root/related.json" capture-merge-in-related.json

python3 - "$fixtures" "$bob_commit" <<'PY'
import json
import pathlib
import sys

fixtures, commit = pathlib.Path(sys.argv[1]), sys.argv[2]
names = sorted(
    p.name for p in fixtures.glob("capture-merge-in-*.json")
    if p.name != "capture-merge-in-manifest.json"
)
manifest = {
    "bob_commit": commit,
    "clock": "2026-11-03 09:30:00",
    "fixtures": names,
}
(fixtures / "capture-merge-in-manifest.json").write_text(
    json.dumps(manifest, indent=2) + "\n"
)
PY
echo "wrote merge-in fixtures to $fixtures (bob $bob_commit)"

#!/usr/bin/env bash
# Generate truthful @route^id Go To fixtures from the bob-cli implementation:
# capture-parse destination fixtures plus capture-complete block-ID browse
# fixtures for the scoped Go To browse. The only vault mutation is creation
# of this isolated synthetic vault.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (for example bob-cli/target/release/bob)." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-caret-goto-fixtures.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-caret-goto-fixture-vault"
vault="$scratch_root/vault"
cache="$scratch_root/cache"
config="$scratch_root/config.yml"
fixtures="$repo_root/Tests/Fixtures"
mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin" "$vault/done" "$cache"

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

cat > "$vault/bob.md" <<'MD'
---
type: "[[area]]"
done_tasks: "[[done/bob_done]]"
---
# Bob

## Tasks
- [*] #task Review the focus area ^focus
- [ ] #task Duplicate one ^duplicate
- [ ] #task Duplicate two ^duplicate
MD

cat > "$vault/taxes.md" <<'MD'
---
type: "[[notebook]]"
template: "[[new_notebook]]"
---
# Taxes

- Refund notes [created::2026-11-14] ^refund-notes
MD

cat > "$vault/done/bob_done.md" <<'MD'
---
type: "[[area]]"
parent: "[[bob]]"
---
# Bob done

- [x] #task An archived task ^archived-focus
MD

export BOB_DIR="$vault"
export BOB_CONFIG_FILE="$config"
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
  local draft="$1" output="$2"
  "$bob_bin" capture-parse --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$output"
}

complete() {
  local draft="$1" cursor="$2" out="$3"
  shift 3
  "$bob_bin" capture-complete -b "$vault" "$@" --cursor "$cursor" --format json -- \
    "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
}

dryrun() {
  local draft="$1" out="$2"
  "$bob_bin" capture --dry-run --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
}

parse '@bob^focus' task-caret-goto-parse-found.json
parse '@bob^archived-focus' task-caret-goto-parse-archived.json
parse '@taxes^refund-notes' task-caret-goto-parse-notebook.json
parse '@bob^focuz' task-caret-goto-parse-missing-block.json
parse '@missing_note^x' task-caret-goto-parse-missing-note.json
parse '@bob^duplicate' task-caret-goto-parse-duplicate.json
# Scoped-browse drafts: the missing-block parse behind the picker plus the
# completion snapshot the picker browses. Cursors sit at each draft's end.
parse '@bob^foc' task-caret-goto-parse-partial.json
complete '@bob^' 5 block-id-goto-empty.json
complete '@bob^foc' 8 block-id-goto-partial.json
parse '@bob^archived' task-caret-goto-parse-archived-partial.json
complete '@bob^archived' 13 block-id-goto-archived.json
parse '@taxes^refund' task-caret-goto-parse-notebook-partial.json
complete '@taxes^refund' 13 block-id-goto-notebook.json
parse '@nope^' task-caret-goto-parse-missing-note-empty.json
complete '@nope^' 6 block-id-goto-missing-note.json
parse '@bob^' task-caret-goto-parse-empty.json
# Mint end-state: body text at the front reverts to today's composer.
parse 'Fix it @bob^new-id' task-caret-goto-parse-mint.json
complete 'Fix it @bob^new-id' 18 block-id-goto-mint.json
dryrun 'Fix it @bob^new-id' capture-dry-run-mint-new-id.json
cp "$vault/bob.md" "$scratch_root/bob.md"
sed '/^-[[:space:]]\[\*\][[:space:]]#task Review the focus area /d' \
  "$scratch_root/bob.md" > "$vault/bob.md"
parse '@bob^focus' task-caret-goto-parse-missing-on-refresh.json
mv "$scratch_root/bob.md" "$vault/bob.md"

python3 - "$fixtures/task-caret-goto-parse-found.json" \
  "$fixtures/task-caret-goto-parse-old-bob.json" <<'PY'
import json
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[1:])
payload = json.loads(source.read_text())
payload.pop("goto", None)
payload["grammar"] = 30
payload["mode"] = "task"
destination.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
PY

python3 - "$fixtures" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
names = [
    "task-caret-goto-parse-found.json",
    "task-caret-goto-parse-archived.json",
    "task-caret-goto-parse-notebook.json",
    "task-caret-goto-parse-missing-block.json",
    "task-caret-goto-parse-missing-note.json",
    "task-caret-goto-parse-duplicate.json",
    "task-caret-goto-parse-missing-on-refresh.json",
    "task-caret-goto-parse-old-bob.json",
]
for name in names[:7]:
    payload = json.loads((root / name).read_text())
    assert payload["mode"] == "task_goto", name
    assert payload["goto"]["status"] in {
        "found", "missing_note", "missing_block_id", "duplicate_block_id"
    }, name
assert json.loads((root / names[0]).read_text())["goto"]["status"] == "found"
assert json.loads((root / names[1]).read_text())["goto"]["landing"]["archived"] is True
assert json.loads((root / names[2]).read_text())["goto"]["landing"]["target_kind"] == "notebook_note"
assert json.loads((root / names[3]).read_text())["goto"]["status"] == "missing_block_id"
assert json.loads((root / names[4]).read_text())["goto"]["status"] == "missing_note"
assert json.loads((root / names[5]).read_text())["goto"]["status"] == "duplicate_block_id"
refresh = json.loads((root / names[6]).read_text())
assert refresh["input"] == "@bob^focus"
assert refresh["goto"]["status"] == "missing_block_id"
old_bob = json.loads((root / names[7]).read_text())
assert old_bob["mode"] == "task" and "goto" not in old_bob

browses = {
    "task-caret-goto-parse-partial.json": ("@bob^foc", "missing_block_id"),
    "task-caret-goto-parse-archived-partial.json": ("@bob^archived", "missing_block_id"),
    "task-caret-goto-parse-notebook-partial.json": ("@taxes^refund", "missing_block_id"),
    "task-caret-goto-parse-missing-note-empty.json": ("@nope^", None),
    "task-caret-goto-parse-empty.json": ("@bob^", None),
}
mint_parse = json.loads((root / "task-caret-goto-parse-mint.json").read_text())
assert mint_parse["input"] == "Fix it @bob^new-id", "mint"
assert mint_parse["mode"] == "task" and "goto" not in mint_parse, "mint"
mint_complete = json.loads((root / "block-id-goto-mint.json").read_text())
assert mint_complete["context"] == "task_block_id", "mint"
assert mint_complete["block_id"]["body"] == "Fix it", "mint"
assert "goto" not in mint_complete["block_id"], "mint"
dry = json.loads((root / "capture-dry-run-mint-new-id.json").read_text())
assert dry["ok"] is True and dry["dry_run"] is True, "mint"
for name, (draft, status) in browses.items():
    payload = json.loads((root / name).read_text())
    assert payload["input"] == draft, name
    if status is None:
        assert payload["mode"] == "incomplete" and "goto" not in payload, name
    else:
        assert payload["mode"] == "task_goto", name
        assert payload["goto"]["status"] == status, name

completes = [
    "block-id-goto-empty.json",
    "block-id-goto-partial.json",
    "block-id-goto-archived.json",
    "block-id-goto-notebook.json",
    "block-id-goto-missing-note.json",
]
for name in completes:
    payload = json.loads((root / name).read_text())
    assert payload["context"] == "task_block_id", name
    block = payload["block_id"]
    assert block["marker"] == "^" and block["intent"] == "new", name
    assert block["body"] == "", name
    goto = block["goto"]
    assert goto["eligible"] is True, name
    assert isinstance(goto["rows"], list), name
    if name == "block-id-goto-missing-note.json":
        assert block["note_exists"] is False, name
        assert goto["rows"] == [], name
    else:
        assert block["note_exists"] is True, name
        assert goto["rows"], name
        assert all("archived" not in row or row["archived"] is False
                   for row in goto["rows"] if row["note_path"] == goto["note_path"]), name
partial = json.loads((root / "block-id-goto-partial.json").read_text())
assert [row["block_id"] for row in partial["block_id"]["goto"]["rows"]] == [
    "focus", "archived-focus",
], "partial rows stay living-then-archive in document order"
PY

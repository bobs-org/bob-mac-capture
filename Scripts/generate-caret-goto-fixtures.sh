#!/usr/bin/env bash
# Generate truthful @route^id Go To fixtures from the bob-cli implementation.
# The only vault mutation is creation of this isolated synthetic vault.
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

parse '@bob^focus' task-caret-goto-parse-found.json
parse '@bob^archived-focus' task-caret-goto-parse-archived.json
parse '@taxes^refund-notes' task-caret-goto-parse-notebook.json
parse '@bob^focuz' task-caret-goto-parse-missing-block.json
parse '@missing_note^x' task-caret-goto-parse-missing-note.json
parse '@bob^duplicate' task-caret-goto-parse-duplicate.json
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
PY

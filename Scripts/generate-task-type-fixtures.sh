#!/usr/bin/env bash
# Generate truthful task-type fixtures from a landed Bob binary.
# Follows Scripts/generate-relation-label-fixtures.sh conventions:
# isolated vault, explicit BOB_BIN (never PATH bob), documented inputs.
#
# Inputs (scratch vault only):
#   plan.default_type: BUILD
#   types: BUILD, FIX, FIXUP, PREFIX, "DEEP WORK", WRITE (config order)
#   area note dev.md with task_type: BUILD and two tasks
#     ^current [type:: FIX], ^inherited (no field)
#   project note sase.md for new-task captures
#   one-task notes for existing-task captures (whole-item ID lookup)
#   daily note 2026/20261030.md plus yesterday's DEEP WORK history
#   BOB_NOW=2026-10-30 09:00:00
#
# Fixtures cover leading/trailing/child parse, prefix and literal
# names, configured/hidden-exact/history-only/typed-unknown completion,
# new and existing subjects, set/cleared/kept captures, all five
# relocation outcomes, a Task Wikilink coexistence case, the incomplete
# `jot idea #` task type, bare-to-typed and leading/trailing/child menu
# requests, separate type markers beside child captures, the R3 refusal for
# a glued marker after `^`, and the retired `t:` prose case. Commit
# operations affect only the scratch vault.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (e.g. bob-cli's CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
scratch_root="$(mktemp -d /tmp/bob-task-type-fixture-vault.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-task-type-fixture-vault"
vault="$scratch_root/vault"
config="$scratch_root/config.yml"
cache="$scratch_root/cache"
fixtures="$repo_root/Tests/Fixtures"
day_file="$vault/2026/20261030.md"
NOW="2026-10-30 09:00:00"
mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin" "$vault/2026" "$cache"
rm -f "$fixtures"/task-type-parse-attached*.json "$fixtures"/task-type-complete-attached*.json
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
cat > "$config" <<'EOF'
plan:
  default_type: BUILD
  max_themes: 30
types:
  BUILD: yellow
  FIX: blue
  FIXUP: red
  PREFIX: magenta
  "DEEP WORK": violet
  WRITE: magenta
EOF
cat > "$vault/dev.md" <<'MD'
---
type: "[[area]]"
task_type: BUILD
---
# Dev

## Tasks
- [ ] #task Current fix [type:: FIX] ^current
    - REQUIREMENTS
        - current contract
- [ ] #task Inherited type ^inherited
MD
cat > "$vault/sase.md" <<'MD'
---
type: "[[project]]"
parent: "[[dev]]"
task_type: WRITE
---
# Sase

## Tasks
MD
cat > "$vault/mac_inbox.md" <<'MD'
---
type: "[[area]]"
task_type: WRITE
---
# Mac inbox

## Tasks
MD

# Existing-task captures use a dedicated one-task note: whole-item
# `^note:id` lookup is prefix-based and fails when siblings share a file.
one_task_note() {
  local stem="$1"
  local title="$2"
  local task="$3"
  cat > "$vault/${stem}.md" <<MD
---
type: "[[project]]"
parent: "[[dev]]"
task_type: WRITE
---
# ${title}

## Tasks
${task}
MD
}

one_task_note kept "Kept" "- [ ] #task Write docs ^write-x"
one_task_note typed "Typed" "- [ ] #task Write docs [type:: WRITE] ^write-y"
one_task_note setx "Set existing" "- [ ] #task Fix parser ^fix-x"
one_task_note ren "Rename running" "- [ ] #task Rename running ^fix-r"
one_task_note app "Append running" "- [ ] #task Append running ^fix-a"
one_task_note mov "Move to existing" "- [ ] #task Move to existing ^fix-m"
one_task_note pln "Rename planned" "- [ ] #task Rename planned ^fix-p"
one_task_note crb "Create below" "- [ ] #task Create below ^fix-c"

cat > "$day_file" <<'MD'
## Pomodoros
- [x] (0800-0830) — FIX
- [x] (0830-0900) — BUILD
MD
cat > "$vault/2026/20261029.md" <<'MD'
## Pomodoros
- [x] () — DEEP WORK
MD

export BOB_DIR="$vault"
export BOB_CONFIG_FILE="$config"
export BOB_DAY_FILE="$day_file"
export BOB_NOW="$NOW"
export XDG_CACHE_HOME="$cache"

assert_json() {
  local out="$1"
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$fixtures/$out"
  then
    echo "fixture $out is not JSON:" >&2
    cat "$fixtures/$out" >&2
    exit 1
  fi
}

persist() {
  python3 - "$1" "$fixtures/$2" "$scratch_root" "$stable_root" <<'PY'
import json
import pathlib
import sys

source, destination, scratch_root, stable_root = sys.argv[1:]
text = pathlib.Path(source).read_text()
for prefix in ("/private" + scratch_root, scratch_root):
    text = text.replace(prefix, stable_root)
json.loads(text)
pathlib.Path(destination).write_text(text)
PY
}

complete() {
  local draft="$1"
  local cursor
  cursor="$(printf '%s' "$draft" | wc -c)"
  local out="$2"
  "$bob_bin" capture-complete -b "$vault" --cursor "$cursor" --format json -- "$draft" \
    > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

complete_at() {
  local draft="$1"
  local cursor="$2"
  local out="$3"
  "$bob_bin" capture-complete -b "$vault" --cursor "$cursor" --format json -- "$draft" \
    > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

parse() {
  local draft="$1"
  local out="$2"
  # capture-parse takes no --bob-dir; BOB_DIR supplies the vault catalog.
  "$bob_bin" capture-parse --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

capture_dry() {
  local out="$1"
  shift
  if ! "$bob_bin" capture -b "$vault" --no-clip --format json -d -- "$@" \
    > "$scratch_root/raw.json"
  then
    echo "capture dry-run failed for $out:" >&2
    cat "$scratch_root/raw.json" >&2
    exit 1
  fi
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

capture_commit() {
  local out="$1"
  shift
  if ! "$bob_bin" capture -b "$vault" --no-clip --format json -- "$@" \
    > "$scratch_root/raw.json"
  then
    echo "capture commit failed for $out:" >&2
    cat "$scratch_root/raw.json" >&2
    exit 1
  fi
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

# Parse: edges, child, literals, refused, prose, routed,
# incomplete task type, wikilink coexistence, retired `t:` (prose).
parse '#' task-type-parse-empty.json
parse '#fix Fix it' task-type-parse-leading.json
parse 'Fix it #fix' task-type-parse-trailing.json
parse '#f' task-type-parse-leading-short.json
parse 'Fix the parser #f' task-type-parse-trailing-prefix.json
parse 'jot idea #f' task-type-parse-typed-trailing.json
parse $'Parent task\n- check the lexer #fi' task-type-parse-child.json
parse 'Fix it #fix' task-type-parse-prefix.json
parse 'Fix it #"DEEP WORK"' task-type-parse-literal.json
parse 'Fix 🧰 it #fix' task-type-parse-unicode.json
parse 'Fix it #nope' task-type-parse-unknown.json
parse 'Ask about #fix today' task-type-parse-midline.json
parse '@dev #f' task-type-parse-routed-empty.json
parse '@dev:current #f' task-type-parse-existing.json
parse 'Follow up ((foo #f' task-type-parse-wikilink-coexist.json
parse 'Fix the parser @dev^parser #fix' task-type-parse-separate-new.json
parse '@dev+current #fix' task-type-parse-separate-existing.json
parse 'note @dev+current #fix' task-type-parse-separate-child.json
parse 'note @dev+current#requirements #fix' task-type-parse-separate-drawer-child.json
parse '@dev^parser#fix' task-type-parse-r3-refusal.json
parse 'jot idea #' task-type-parse-incomplete-marker.json
parse 'Fix it t:fix' task-type-parse-retired.json

# Completion: empty, leading/trailing, prefix, refused, new/existing
# subjects, child/second-line, adjacent route, wikilink, and incomplete marker.
complete 'Fix the parser @dev^parser #' task-type-complete-empty.json
complete '@dev #f' task-type-complete-new.json
complete 'Fix it #fix' task-type-complete-prefix.json
complete 'Fix it #fixs' task-type-complete-typed-unknown.json
complete '@dev:current #f' task-type-complete-existing-current.json
complete '@dev:inherited #f' task-type-complete-existing-inherited.json
complete '@dev+current #' task-type-complete-existing-empty.json
complete $'Parent task\n- check the lexer #fi' task-type-complete-child.json
complete $'Parent task\n #fi' task-type-complete-second-line.json
complete_at '@de #fix' 3 task-type-complete-adjacent-route.json
complete 'Follow up ((foo #f' task-type-complete-wikilink-coexist.json
complete_at 'Follow up ((foo #f' 14 task-type-complete-wikilink-query.json
complete 'jot idea #' task-type-complete-incomplete-marker.json
complete 'Fix the parser @dev^parser #fix' task-type-complete-separate-new.json
complete '@dev+current #fix' task-type-complete-separate-existing.json
complete 'note @dev+current #fix' task-type-complete-separate-child.json
complete 'note @dev+current#requirements #fix' task-type-complete-separate-drawer-child.json
complete '#f' task-type-complete-leading.json
complete '#fix Fix it' task-type-complete-leading-full.json
complete 'Fix the parser #f' task-type-complete-trailing-prefix.json
complete 'jot idea #f' task-type-complete-typed-trailing.json
complete_at '#fix Fix it' 4 task-type-complete-leading-prefix.json

# Hidden-exact: hide FIX from Recent, then complete empty vs exact.
"$bob_bin" themes hide FIX --via fixture --format json >/dev/null
complete 'Fix the parser @dev^parser #' task-type-complete-empty-hidden.json
complete '#fix' task-type-complete-hidden-exact.json
"$bob_bin" themes unhide FIX --via fixture --format json >/dev/null

# History-only: unconfigured vocabulary uses history order.
cat > "$scratch_root/config-history.yml" <<'EOF'
plan:
  default_type: BUILD
  max_themes: 30
EOF
history_draft='Fix the parser @dev^parser #'
BOB_CONFIG_FILE="$scratch_root/config-history.yml" \
  "$bob_bin" capture-complete -b "$vault" --cursor "${#history_draft}" --format json -- "$history_draft" \
  > "$fixtures/task-type-complete-history.json"
assert_json task-type-complete-history.json

# Captures: set / kept / cleared on new and existing tasks.
capture_dry task-type-capture-set.json 'Fix the parser #fix' '@sase'
capture_dry task-type-capture-kept-inherited.json '^kept:write-x' '#write'
capture_dry task-type-capture-cleared.json '^typed:write-y' '#write'
cat > "$day_file" <<'MD'
## Pomodoros
- [ ] () — FIX
MD
capture_dry task-type-capture-set-existing.json '^setx:fix-x' '#fix'

# Relocations: seed a dedicated day file per outcome, then dry-run retype.
relocate() {
  local stem="$1"
  local id="$2"
  local day="$3"
  local out="$4"
  cat > "$day_file" <<MD
## Pomodoros
$day
MD
  capture_dry "$out" "^${stem}:${id}" "#fix"
}

relocate ren fix-r $'- [ ] (**0900-1000**) — BUILD\n  - [[ren#^fix-r]]\n' \
  task-type-capture-rename-entry.json
relocate app fix-a $'- [ ] (**0900-1000**) — BUILD\n  - [[app#^fix-a]]\n  - [[app#^nbr]]\n' \
  task-type-capture-append-component.json
relocate mov fix-m $'- [ ] () — BUILD\n  - [[mov#^fix-m]]\n- [ ] () — FIX\n' \
  task-type-capture-move-to.json
relocate pln fix-p $'- [ ] () — BUILD\n  - [[pln#^fix-p]]\n' \
  task-type-capture-rename-placeholder.json
relocate crb fix-c $'- [ ] () — BUILD\n  - [[crb#^fix-c]]\n  - [[crb#^nbr]]\n' \
  task-type-capture-create-below.json

# One committed capture so dry-run and write JSON can be compared.
cat > "$day_file" <<'MD'
## Pomodoros
- [ ] () — FIX
MD
capture_commit task-type-capture-set-existing-commit.json '^setx:fix-x' '#fix'

echo "Generated task-type fixtures with $($bob_bin --version | head -n 1)"

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
# Fixtures cover empty/leading/trailing/child parse, prefix and literal
# names, configured/hidden-exact/history-only/typed-unknown completion,
# new and existing subjects, set/cleared/kept captures, all five
# relocation outcomes, and a Task Wikilink plus trailing `t:` coexistence
# case. Commit operations affect only the scratch vault.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (e.g. bob-cli's CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
scratch_root="$(mktemp -d /tmp/bob-task-type-fixture-vault.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
vault="$scratch_root/vault"
config="$scratch_root/config.yml"
cache="$scratch_root/cache"
fixtures="$repo_root/Tests/Fixtures"
day_file="$vault/2026/20261030.md"
NOW="2026-10-30 09:00:00"
mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin" "$vault/2026" "$cache"
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

complete() {
  local draft="$1"
  local cursor
  cursor="$(printf '%s' "$draft" | wc -c)"
  local out="$2"
  "$bob_bin" capture-complete -b "$vault" --cursor "$cursor" --format json -- "$draft" \
    > "$fixtures/$out"
  assert_json "$out"
}

complete_at() {
  local draft="$1"
  local cursor="$2"
  local out="$3"
  "$bob_bin" capture-complete -b "$vault" --cursor "$cursor" --format json -- "$draft" \
    > "$fixtures/$out"
  assert_json "$out"
}

parse() {
  local draft="$1"
  local out="$2"
  # capture-parse takes no --bob-dir; BOB_DIR supplies the vault catalog.
  "$bob_bin" capture-parse --format json -- "$draft" > "$fixtures/$out"
  assert_json "$out"
}

capture_dry() {
  local out="$1"
  shift
  if ! "$bob_bin" capture -b "$vault" --no-clip --format json -d -- "$@" > "$fixtures/$out"
  then
    echo "capture dry-run failed for $out:" >&2
    cat "$fixtures/$out" >&2
    exit 1
  fi
  assert_json "$out"
}

capture_commit() {
  local out="$1"
  shift
  if ! "$bob_bin" capture -b "$vault" --no-clip --format json -- "$@" > "$fixtures/$out"
  then
    echo "capture commit failed for $out:" >&2
    cat "$fixtures/$out" >&2
    exit 1
  fi
  assert_json "$out"
}

# Parse: empty, leading, trailing, child, prefix, literal, unicode, unknown,
# mid-line prose (no type span).
parse 't:' task-type-parse-empty.json
parse 't:fix Fix it' task-type-parse-leading.json
parse 'Fix it t:fix' task-type-parse-trailing.json
parse $'Parent task\n- check the lexer t:fi' task-type-parse-child.json
parse 'Fix it t:fix' task-type-parse-prefix.json
parse 'Fix it t:"DEEP WORK"' task-type-parse-literal.json
parse 'Fix 🧰 it t:fix' task-type-parse-unicode.json
parse 'Fix it t:nope' task-type-parse-unknown.json
parse 'Ask about t:fix today' task-type-parse-midline.json
parse '@dev t:' task-type-parse-routed-empty.json
parse '@dev:current t:' task-type-parse-existing.json
parse 'Follow up ((foo t:' task-type-parse-wikilink-coexist.json

# Completion: empty leading/trailing, prefix, literal, new/existing subjects.
complete 't:' task-type-complete-empty.json
complete '@dev t:' task-type-complete-new.json
complete 'Fix it t:fix' task-type-complete-prefix.json
complete 'Fix it t:fixs' task-type-complete-typed-unknown.json
complete '@dev:current t:' task-type-complete-existing-current.json
complete '@dev:inherited t:' task-type-complete-existing-inherited.json
complete $'Parent task\n- check the lexer t:fi' task-type-complete-child.json
complete $'Parent task\n t:fi' task-type-complete-second-line.json
complete_at '@de t:fix' 3 task-type-complete-adjacent-route.json
complete 'Follow up ((foo t:' task-type-complete-wikilink-coexist.json
complete_at 'Follow up ((foo t:' 14 task-type-complete-wikilink-query.json

# Hidden-exact: hide FIX from Recent, then complete empty vs exact.
"$bob_bin" themes hide FIX --via fixture --format json >/dev/null
complete 't:' task-type-complete-empty-hidden.json
complete 't:fix' task-type-complete-hidden-exact.json
"$bob_bin" themes unhide FIX --via fixture --format json >/dev/null

# History-only: unconfigured vocabulary uses history order.
cat > "$scratch_root/config-history.yml" <<'EOF'
plan:
  default_type: BUILD
  max_themes: 30
EOF
BOB_CONFIG_FILE="$scratch_root/config-history.yml" \
  "$bob_bin" capture-complete -b "$vault" --cursor 2 --format json -- 't:' \
  > "$fixtures/task-type-complete-history.json"
assert_json task-type-complete-history.json

# Captures: set / kept / cleared on new and existing tasks.
capture_dry task-type-capture-set.json 'Fix the parser t:fix' '@sase'
capture_dry task-type-capture-kept-inherited.json '^kept:write-x' 't:write'
capture_dry task-type-capture-cleared.json '^typed:write-y' 't:write'
cat > "$day_file" <<'MD'
## Pomodoros
- [ ] () — FIX
MD
capture_dry task-type-capture-set-existing.json '^setx:fix-x' 't:fix'

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
  capture_dry "$out" "^${stem}:${id}" "t:fix"
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
capture_commit task-type-capture-set-existing-commit.json '^setx:fix-x' 't:fix'

echo "Generated task-type fixtures with $($bob_bin --version | head -n 1)"

#!/usr/bin/env bash
# Generate list fixtures (a lone `@file` header over bullets) from a real Bob.
#
#   BOB_BIN=/path/to/CARGO_TARGET_DIR/debug/bob BOB_CLI_DIR=/path/to/bob-cli \
#     Scripts/generate-list-fixtures.sh
#
# BOB_BIN must be built from the bob-cli checkout named by BOB_CLI_DIR, and that
# checkout must contain the list block-ID editor assists (commit 35c46693) with a clean
# tree, because the binary carries no git revision of its own. The script verifies it
# reports `grammar >= 6`, then persists, from one isolated vault, config, cache, state,
# HOME, and pinned clock:
#
#   list-parse-*.json     bob capture-parse
#   list-complete-*.json  bob capture-complete (the `project_task_block_id` context)
#   list-capture-*.json   bob capture --dry-run
#
# Every capture is a dry run, so Bob writes nothing, and the scratch directory is removed
# on exit. Only the scratch root inside Bob's output is rewritten to a stable path. The
# script also writes Tests/Fixtures/list-fixtures-README.md, which records the Bob
# version, bob-cli revision, and every input.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
cli_dir="${BOB_CLI_DIR:-}"
prerequisite_commit="35c46693"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a bob binary built from BOB_CLI_DIR (for example CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
if [[ -z "$cli_dir" ]] || ! git -C "$cli_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Set BOB_CLI_DIR to the bob-cli checkout that BOB_BIN was built from." >&2
  exit 1
fi
if ! git -C "$cli_dir" merge-base --is-ancestor "$prerequisite_commit" HEAD; then
  echo "BOB_CLI_DIR does not contain the list prerequisite $prerequisite_commit." >&2
  exit 1
fi
if [[ -n "$(git -C "$cli_dir" status --porcelain)" ]]; then
  echo "BOB_CLI_DIR has uncommitted changes; build and record a clean revision." >&2
  exit 1
fi
cli_revision="$(git -C "$cli_dir" rev-parse HEAD)"

scratch_root="$(mktemp -d /tmp/bob-mac-capture-list-fixture-scratch.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-list-fixture"
fixtures="$repo_root/Tests/Fixtures"
rm -f "$fixtures"/list-parse-*.json "$fixtures"/list-complete-*.json "$fixtures"/list-capture-*.json
vault="$scratch_root/vault"
day_file="$vault/2026/20261030.md"
config="$scratch_root/config.yml"
mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin" "$vault/2026" \
  "$scratch_root/"{home,config,state,cache}

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
  WRITE: magenta
EOF
# dev.md is the list destination: one existing task and an Ideas section for section lists.
cat > "$vault/dev.md" <<'EOF'
---
type: "[[area]]"
---
# Dev

## Tasks

- [ ] #task Existing thing [created::2026-10-01] ^existing

## Ideas

- An old idea
EOF
# cash.md hosts the project-note parity prompt (`Finish it @cash^goog-exit@`).
cat > "$vault/cash.md" <<'EOF'
---
type: "[[area]]"
---
# Cash

## Tasks

- [ ] #task Existing cash thing [created::2026-10-01] ^cash-existing
EOF
printf '## Pomodoros\n- [ ] (0900-0930) — FIX\n' > "$day_file"
find "$vault" -name '*.md' -exec touch -d '2026-10-29 12:00:00 UTC' {} +

# Every Bob call runs in a cleared environment so nothing from the real home, vault,
# config, display, or clipboard can leak into a fixture.
bob() {
  env -i \
    PATH="$PATH" \
    HOME="$scratch_root/home" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$config" \
    BOB_DIR="$vault" \
    BOB_DAY_FILE="$day_file" \
    BOB_NOW="2026-10-30 09:15:00" \
    TZ="UTC0" \
    "$bob_bin" "$@"
}

version_line="$("$bob_bin" --version | head -n 1)"
probe="$scratch_root/probe.json"
bob capture-parse --format json -- 'probe' > "$probe"
python3 - "$probe" <<'PY'
import json
import pathlib
import sys

grammar = json.loads(pathlib.Path(sys.argv[1]).read_text()).get("grammar")
if not isinstance(grammar, int) or grammar < 6:
    sys.exit(f"BOB_BIN reports grammar {grammar!r}; rebuild it from a bob-cli with grammar >= 6")
PY

manifest="$scratch_root/manifest.md"
{
  echo "| Fixture | Command | Input |"
  echo "| --- | --- | --- |"
} > "$manifest"

# Persist one raw Bob reply with only the unstable scratch root rewritten.
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

record() {
  local text="${3//$'\n'/\\n}"
  text="${text//|/\\|}"
  printf '| `%s` | `%s` | `%s` |\n' "$1" "$2" "$text" >> "$manifest"
}

parse() {
  bob capture-parse --format json -- "$2" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$1"
  record "$1" "capture-parse" "$2"
}

# The caret sits at the end of the draft, where a typed ` :` or ` ^` leaves it.
complete() {
  local cursor
  cursor="$(printf '%s' "$2" | wc -c | tr -d ' ')"
  bob capture-complete -b "$vault" --cursor "$cursor" --format json -- "$2" \
    > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$1"
  record "$1" "capture-complete --cursor $cursor" "$2"
}

capture() {
  bob capture -b "$vault" --format json --dry-run --no-clip -- "$2" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$1"
  record "$1" "capture --dry-run --no-clip" "$2"
}

# The worked example before and after Bryan accepts the nested prompt: the ID moves from
# the nested line onto the owner line.
worked_before=$'@dev\n- Fix flaky gkeep test\n  - repro on CI first :\n- Write release notes ^release-notes s:2\n- Ping Alice about the cutover'
worked_after=$'@dev\n- Fix flaky gkeep test :fix-flaky-gkeep\n  - repro on CI first\n- Write release notes ^release-notes s:2\n- Ping Alice about the cutover'
section_list=$'@dev#Ideas\n- idea one\n  - detail\n- idea two'

# --- capture-parse ---
parse list-parse-worked.json "$worked_after"
parse list-parse-nested-prompt.json $'@dev\n- Fix flaky gkeep test\n  - repro on CI first :'
parse list-parse-header-only.json '@dev'
parse list-parse-section.json "$section_list"

# --- capture-complete: the block-ID prompt on a list bullet ---
complete list-complete-same-line.json $'@dev\n- Fix flaky gkeep test :'
complete list-complete-nested.json $'@dev\n- Fix flaky gkeep test\n  - repro on CI first :'
complete list-complete-nested-owner-id.json \
  $'@dev\n- Fix flaky gkeep test :old-id\n  - repro on CI first :'
complete list-complete-nested-caret.json $'@dev\n- Fix flaky gkeep test\n  - repro on CI first ^'
complete list-complete-project-note-same-line.json \
  $'Finish it @cash^goog-exit@\n- Draft the memo :'
complete list-complete-project-note-nested.json \
  $'Finish it @cash^goog-exit@\n- Draft the memo\n  - outline first :'

# --- capture --dry-run: where each bullet lands ---
capture list-capture-tasks.json "$worked_after"
capture list-capture-notes.json "$section_list"

# Self-checks: every fixture parses, and raw Bob replies carry the contract the Mac decodes.
python3 - "$fixtures" "$worked_before" "$worked_after" <<'PY'
import json
import pathlib
import sys

fixtures = pathlib.Path(sys.argv[1])
worked_before, worked_after = sys.argv[2:4]


def load(name):
    return json.loads((fixtures / name).read_text())


def apply_splice(draft, field):
    splice = field["splice"]
    raw = draft.encode()
    start, end = splice["range"]["start"], splice["range"]["end"]
    insertion = (splice["before"] + field["suggestions"][0] + splice["after"]).encode()
    return (raw[:start] + insertion + raw[end:]).decode()


for path in sorted(fixtures.glob("list-*.json")):
    json.loads(path.read_text())

parsed = load("list-parse-worked.json")
assert parsed["grammar"] >= 6
assert [item["mode"] for item in parsed["items"]] == ["pomodoro_task", "task", "task"]
assert all(item["list"]["kind"] == "tasks" for item in parsed["items"])
assert [item["list"]["position"] for item in parsed["items"]] == [1, 2, 3]
assert all(item["list"]["count"] == 3 for item in parsed["items"])
assert parsed["items"][0]["block_id"] == "fix-flaky-gkeep"

pending = load("list-parse-nested-prompt.json")
assert pending["needs"] == ["block_id"]

header = load("list-parse-header-only.json")
assert header["items"][0]["needs"] == ["list_item"]
assert header["items"][0]["list"]["count"] == 0
assert header["items"][0]["line_start"] == header["items"][0]["line_end"] == 1

section = load("list-parse-section.json")
assert [item["list"]["kind"] for item in section["items"]] == ["notes", "notes"]
assert section["items"][0]["list"]["section"] == "Ideas"

same = load("list-complete-same-line.json")
assert same["context"] == "project_task_block_id"
assert same["block_id"]["owner_line"] == 2
assert same["block_id"]["splice"] == {
    "range": same["replacement"],
    "before": "",
    "after": "",
}

nested = load("list-complete-nested.json")
field = nested["block_id"]
assert field["owner_line"] == 2
assert field["body"] == "Fix flaky gkeep test"
assert field["suggestions"][0] == "fix-flaky-gkeep"
assert field["splice"]["before"] == " :"
assert field["splice"]["after"] == "\n  - repro on CI first"
spliced = apply_splice(worked_before.split("\n- Write")[0], field)
assert spliced == worked_after.split("\n- Write")[0], spliced

owner_id = load("list-complete-nested-owner-id.json")["block_id"]
assert owner_id["owner_line"] == 2
assert owner_id["splice"]["before"] == ":"
assert owner_id["suggestions"][0] == "old-id"

caret = load("list-complete-nested-caret.json")["block_id"]
assert caret["marker"] == "^" and caret["splice"]["before"] == " ^"

project_same = load("list-complete-project-note-same-line.json")
assert project_same["block_id"]["owner_line"] == 2
assert project_same["block_id"]["splice"] == {
    "range": project_same["replacement"],
    "before": "",
    "after": "",
}

project = load("list-complete-project-note-nested.json")["block_id"]
assert project["route"] == "cash_goog_exit" and project["owner_line"] == 2
assert project["splice"]["before"] == " :"

tasks = load("list-capture-tasks.json")
assert [item["list"]["position"] for item in tasks["captures"]] == [1, 2, 3]
assert all(item["list"]["route"] == "dev" for item in tasks["captures"])
assert tasks["captures"][0]["block_link"] == "[[dev#^fix-flaky-gkeep]]"

notes = load("list-capture-notes.json")
assert [item["list"]["kind"] for item in notes["captures"]] == ["notes", "notes"]
assert all(item["list"]["section"] == "Ideas" for item in notes["captures"])
PY

{
  echo "# List fixtures"
  echo
  echo "Generated by \`Scripts/generate-list-fixtures.sh\`:"
  echo
  echo '```bash'
  echo 'BOB_BIN=/path/to/CARGO_TARGET_DIR/debug/bob BOB_CLI_DIR=/path/to/bob-cli \'
  echo '  Scripts/generate-list-fixtures.sh'
  echo '```'
  echo
  echo "Generated with \`${version_line}\` built from bob-cli revision \`${cli_revision}\`"
  echo "(grammar revision 6, \`schema_version\` 1). The script requires commit \`${prerequisite_commit}\`"
  echo "and a clean bob-cli checkout. All JSON fixtures below are raw Bob replies, with only"
  echo "the temporary vault path rewritten to \`${stable_root}\`."
  echo
  echo "Inputs use an isolated vault with \`dev.md\` (task \`^existing\` and an Ideas section),"
  echo "\`cash.md\`, a daily FIX Pomodoro, configured types, and"
  echo "\`BOB_NOW=2026-10-30 09:15:00\`. Every capture is a dry run with \`--no-clip\`."
  echo
  echo "## Raw fixtures"
  echo
  cat "$manifest"
} > "$fixtures/list-fixtures-README.md"

echo "Generated list fixtures with ${version_line} (bob-cli ${cli_revision})"

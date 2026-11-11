#!/usr/bin/env bash
# Generate drawer and first-level bullet drawer fixtures from a real Bob.
#
#   BOB_BIN=/path/to/CARGO_TARGET_DIR/debug/bob BOB_CLI_DIR=/path/to/bob-cli \
#     Scripts/generate-drawer-fixtures.sh
#
# BOB_BIN must be built from the bob-cli checkout named by BOB_CLI_DIR, and that
# checkout must contain the grammar-4 capture drawer work (commit 971d864f) with a clean
# tree, because the binary carries no git revision of its own. The script verifies it
# reports `grammar >= 26`, including Bob-authored `place_menu` chrome, then persists,
# from one isolated vault, config, cache, state,
# HOME, and pinned clock:
#
#   drawer-parse-*.json           bob capture-parse
#   drawer-complete-*.json        bob capture-complete (the `drawer` context)
#   drawer-bullet-complete-*.json bob capture-complete (bullet drawer context)
#   drawer-capture-*.json         bob capture --dry-run
#   drawer-list-*.json       bob capture-drawers (task drawers plus catalog recents)
#
# Every capture is a dry run, so Bob writes nothing, and the scratch directory is removed
# on exit. Only the scratch root inside Bob's output is rewritten to a stable path. The
# script also writes Tests/Fixtures/drawer-fixtures-README.md, which records the Bob
# version, bob-cli revision, and every input.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
cli_dir="${BOB_CLI_DIR:-}"
prerequisite_commit="971d864f"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a bob binary built from BOB_CLI_DIR (for example CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
if [[ -z "$cli_dir" ]] || ! git -C "$cli_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Set BOB_CLI_DIR to the bob-cli checkout that BOB_BIN was built from." >&2
  exit 1
fi
if ! git -C "$cli_dir" merge-base --is-ancestor "$prerequisite_commit" HEAD; then
  echo "BOB_CLI_DIR does not contain the grammar-4 prerequisite $prerequisite_commit." >&2
  exit 1
fi
if [[ -n "$(git -C "$cli_dir" status --porcelain)" ]]; then
  echo "BOB_CLI_DIR has uncommitted changes; build and record a clean revision." >&2
  exit 1
fi
cli_revision="$(git -C "$cli_dir" rev-parse HEAD)"

scratch_root="$(mktemp -d /tmp/bob-mac-capture-drawer-fixture-scratch.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-drawer-fixture"
fixtures="$repo_root/Tests/Fixtures"
rm -f "$fixtures"/drawer-contr*.json
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
# foo.md holds the target (`^bar`, two drawers) and a task without drawers (`^plain`).
# other1-3.md each use MOTIVATION and ACCEPTANCE so both clear the catalog's
# "used in at least two notes" bar and appear as Recent.
cat > "$vault/foo.md" <<'EOF'
---
type: "[[area]]"
---
# Foo

## Tasks
- [ ] #task Upgrade Postgres [created::2026-10-01] ^bar
	- REQUIREMENTS
		- 2 GB RAM
		- 4 CPUs
		- fast disk
	- FUTURE WORK
		- sharding
- [ ] #task Plain task [created::2026-10-01] ^plain
EOF
cat > "$vault/project.md" <<'EOF'
---
type: "[[project]]"
---
# Project
- [ ] #task #prj Deliver first release ^prj

## Requirements
- signed package
- rollback path

## Pomodoros
- [ ] (0900-0930) — FIX

## Q&A
- pending owner
EOF
for n in 1 2 3; do
  cat > "$vault/other$n.md" <<EOF
---
type: "[[area]]"
---
# Other $n

## Tasks
- [ ] #task Thing [created::2026-10-01] ^t$n
	- MOTIVATION
		- why
	- ACCEPTANCE
		- done when
EOF
done
printf '## Pomodoros\n- [ ] (0900-0930) — FIX\n' > "$day_file"
# Pin note mtimes so the catalog's `last_seen` is the same on every run.
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
if not isinstance(grammar, int) or grammar < 26:
    sys.exit(f"BOB_BIN reports grammar {grammar!r}; rebuild it from a bob-cli with grammar >= 26")
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

list_drawers() {
  local out="$1" route="$2" block_id="$3"
  bob capture-drawers -b "$vault" -r "$route" -i "$block_id" -f json > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  record "$out" "capture-drawers -r $route -i $block_id" "$block_id"
}

# --- capture-parse: the glued `#` after `+id` ---
parse drawer-parse-empty.json 'Postgres 17 minimum @foo+bar#'
parse drawer-parse-typed.json 'Postgres 17 minimum @foo+bar#req'
parse drawer-parse-existing.json 'Postgres 17 minimum @foo+bar#requirements'
parse drawer-parse-new.json 'Postgres 17 minimum @foo+bar#perf-budget'
parse drawer-parse-literal.json 'Postgres 17 minimum @foo+bar#"Q&A"'

# --- capture-complete: the `drawer` context ---
complete drawer-complete-empty.json 'Postgres 17 minimum @foo+bar#'
complete drawer-complete-typed-match.json 'Postgres 17 minimum @foo+bar#req'
complete drawer-complete-typed-none.json 'Postgres 17 minimum @foo+bar#perf'
complete drawer-complete-typed-recent.json 'Postgres 17 minimum @foo+bar#mot'
complete drawer-complete-typed-reserved.json 'Postgres 17 minimum @foo+bar#tasks'
complete drawer-complete-plain-task.json 'Postgres 17 minimum @foo+plain#'
complete drawer-complete-missing-target.json 'Postgres 17 minimum @foo+nope#'

# --- capture --dry-run: where the bullet lands ---
capture drawer-capture-existing.json 'Postgres 17 minimum @foo+bar#requirements'
capture drawer-capture-new.json 'Postgres 17 minimum @foo+bar#perf-budget'
capture drawer-capture-plain-child.json 'Postgres 17 minimum @foo+bar'

# --- capture --dry-run: retype an existing task beside a new drawer ---
capture drawer-capture-new-retype.json 'Postgres 17 minimum @foo+bar#perf-budget #fix'

# --- Several notes on one existing task: new drawer and plain-note summaries ---
capture drawer-capture-multi-note.json $'@foo+bar\n- Ping Alice about the cutover\n- REQUIREMENTS\n  - Postgres 17 minimum\n- RISKS\n  - Try logical replication\n- Benchmarks look fine\n  - p99 under 40 ms'

# --- Bullet drawer menus: existing task, new task, and a typed query ---
complete drawer-bullet-complete-existing-empty.json $'@foo+bar\n- #'
complete drawer-bullet-complete-new-task-empty.json $'New task\n- #'
complete drawer-bullet-complete-existing-typed.json $'@foo+bar\n- #req'

# --- ^prj drawers: project H2s and their creation behavior ---
parse drawer-parse-project.json 'Review release criteria @project+prj#requirements'
complete drawer-complete-project-empty.json 'Review release criteria @project+prj#'
complete drawer-complete-project-typed.json 'Review release criteria @project+prj#req'
capture drawer-capture-project-existing.json 'Review release criteria @project+prj#requirements'
capture drawer-capture-project-new.json 'Add owner @project+prj#new-area'

# --- capture-drawers: the CLI behind the menu ---
list_drawers drawer-list.json foo bar
list_drawers drawer-list-empty.json foo plain
list_drawers drawer-list-project.json project prj

# Self-checks: every fixture parses, and raw Bob replies carry the contract the Mac decodes.
python3 - "$fixtures" <<'PY'
import json
import pathlib
import sys

fixtures = pathlib.Path(sys.argv[1])


def load(name):
    return json.loads((fixtures / name).read_text())


for path in sorted(fixtures.glob("drawer-*.json")):
    json.loads(path.read_text())

parsed = load("drawer-parse-empty.json")
assert parsed["needs"] == ["drawer"]
new_span = next(span for span in load("drawer-parse-new.json")["spans"] if span["kind"] == "drawer")
assert new_span["title"] == "PERF BUDGET" and new_span["key"] == "PERF BUDGET"
assert parsed["grammar"] >= 26

empty = load("drawer-complete-empty.json")
assert empty["context"] == "drawer" and empty["target"]["block_id"] == "bar"
assert empty["initial_selection"] == "none"
assert empty["place_menu"]["kind"] == "drawer"
assert empty["place_menu"]["title"] == "Drawer"
assert [row["group"] for row in empty["candidates"]] == ["task", "task", "recent", "recent"]
assert all(row["replacement"].startswith("#") for row in empty["candidates"])
plain_task_rows = load("drawer-complete-plain-task.json")["candidates"]
assert [row["group"] for row in plain_task_rows] == ["recent", "recent", "recent"]
missing = load("drawer-complete-missing-target.json")
assert missing["candidates"] == [] and missing["warnings"]
assert load("drawer-complete-typed-none.json")["candidates"][0]["group"] == "new"
assert [row["group"] for row in load("drawer-complete-typed-recent.json")["candidates"]] == ["recent", "new"]
assert any(row.get("refused") for row in load("drawer-complete-typed-reserved.json")["candidates"])

existing = load("drawer-capture-existing.json")["drawer"]
assert existing == {"title": "REQUIREMENTS", "key": "REQUIREMENTS", "created": False}
created = load("drawer-capture-new.json")["drawer"]
assert created == {"title": "PERF BUDGET", "key": "PERF BUDGET", "created": True}
assert load("drawer-capture-new-retype.json")["drawer"]["created"] is True
assert load("drawer-capture-new-retype.json")["task_theme"]["theme"]["name"] == "FIX"
assert load("drawer-capture-plain-child.json").get("drawer") is None
assert load("drawer-list.json")["count"] == 2
assert load("drawer-list-empty.json")["count"] == 0

project_menu = load("drawer-complete-project-empty.json")
assert project_menu["target"]["block_id"] == "prj"
assert project_menu["candidates"][0]["title"] == "Requirements"
assert load("drawer-capture-project-existing.json")["drawer"]["title"] == "Requirements"
assert load("drawer-capture-project-new.json")["drawer"]["created"] is True
assert load("drawer-list-project.json")["count"] == 2

multi = load("drawer-capture-multi-note.json")
assert len(multi["notes"]) == 4
assert [drawer["title"] for drawer in multi["drawers"]] == ["REQUIREMENTS", "RISKS"]
assert [drawer["created"] for drawer in multi["drawers"]] == [False, True]

bullet_existing = load("drawer-bullet-complete-existing-empty.json")
assert bullet_existing["context"] == "drawer"
assert bullet_existing["target"]["block_id"] == "bar"
assert bullet_existing["initial_selection"] == "none"
assert any("\n  - " in row["replacement"] for row in bullet_existing["candidates"])
bullet_new = load("drawer-bullet-complete-new-task-empty.json")
assert bullet_new["context"] == "drawer"
assert bullet_new["target"]["block_id"] is None
assert bullet_new["target"]["text"] == "New task"
typed_bullet = load("drawer-bullet-complete-existing-typed.json")
assert typed_bullet["context"] == "drawer" and typed_bullet["query"] == "req"
PY

{
  echo "# Drawer fixtures"
  echo
  echo "Generated by \`Scripts/generate-drawer-fixtures.sh\`:"
  echo
  echo '```bash'
  echo 'BOB_BIN=/path/to/CARGO_TARGET_DIR/debug/bob BOB_CLI_DIR=/path/to/bob-cli \'
  echo '  Scripts/generate-drawer-fixtures.sh'
  echo '```'
  echo
  echo "Generated with \`${version_line}\` built from bob-cli revision \`${cli_revision}\`"
  echo "(grammar revision 26, \`schema_version\` 1). The script requires commit \`${prerequisite_commit}\`"
  echo "and a clean bob-cli checkout. All JSON fixtures below are raw Bob replies, with only"
  echo "the temporary vault path rewritten to \`${stable_root}\`."
  echo
  echo "Inputs use an isolated vault with task \`^bar\`, task \`^plain\`, a project-note"
  echo "\`^prj\` with H2 drawers, catalog notes, configured types, a daily FIX Pomodoro, and"
  echo "\`BOB_NOW=2026-10-30 09:15:00\`. Every capture is a dry run with \`--no-clip\`."
  echo
  echo "## Raw fixtures"
  echo
  cat "$manifest"
} > "$fixtures/drawer-fixtures-README.md"

echo "Generated drawer fixtures with ${version_line} (bob-cli ${cli_revision})"

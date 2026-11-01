#!/usr/bin/env bash
# Generate drawer (`@route+id#drawer`) fixtures from a real Bob, plus clearly labeled
# synthetic overlays for the drawer-menu fields that Bob does not emit yet.
#
#   BOB_BIN=/path/to/target/debug/bob BOB_CLI_DIR=/path/to/bob-cli \
#     Scripts/generate-drawer-fixtures.sh
#
# BOB_BIN must be built from the bob-cli checkout named by BOB_CLI_DIR, and that
# checkout must contain the grammar-3 drawer work (commit e660c8d8) with a clean tree,
# because the binary carries no git revision of its own. The script verifies the binary
# reports `grammar >= 3`, then persists, from one isolated vault, config, cache, state,
# HOME, and pinned clock:
#
#   drawer-parse-*.json      bob capture-parse
#   drawer-complete-*.json   bob capture-complete (the `drawer` context)
#   drawer-capture-*.json    bob capture --dry-run
#   drawer-list-*.json       bob capture-drawers (task drawers plus catalog recents)
#
# Everything above is raw Bob output. Bob's drawer menu does not yet emit every field the
# plan's contract defines (the Recent and New groups, `detail`, `consequence`, `refused`,
# `initial_selection: none`, the per-item `drawer` object, and a separate `#type` retype
# beside a drawer). Those cases are written as `drawer-contract-*.json`: the real fixture
# for the same draft with only the missing fields overlaid. They are synthetic, the README
# says so, and the script records, from the real fixtures, which fields Bob still omits. A
# fixture stops being synthetic when that list empties; then delete its overlay here.
#
# Every capture is a dry run, so Bob writes nothing, and the scratch directory is removed
# on exit. Only the scratch root inside Bob's output is rewritten to a stable path. The
# script also writes Tests/Fixtures/drawer-fixtures-README.md, which records the Bob
# version, bob-cli revision, and every input.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
cli_dir="${BOB_CLI_DIR:-}"
prerequisite_commit="e660c8d8"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a bob binary built from BOB_CLI_DIR (for example its target/debug/bob)." >&2
  exit 1
fi
if [[ -z "$cli_dir" ]] || ! git -C "$cli_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Set BOB_CLI_DIR to the bob-cli checkout that BOB_BIN was built from." >&2
  exit 1
fi
if ! git -C "$cli_dir" merge-base --is-ancestor "$prerequisite_commit" HEAD; then
  echo "BOB_CLI_DIR does not contain the grammar-3 prerequisite $prerequisite_commit." >&2
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
if not isinstance(grammar, int) or grammar < 3:
    sys.exit(f"BOB_BIN reports grammar {grammar!r}; rebuild it from a bob-cli with grammar >= 3")
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
  bob capture-drawers -b "$vault" -r foo -i "$2" -f json > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$1"
  record "$1" "capture-drawers -r foo -i $2" "$2"
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

# --- capture-drawers: the CLI behind the menu ---
list_drawers drawer-list.json bar
list_drawers drawer-list-empty.json plain

# A retype beside a drawer is a plan requirement Bob does not honor yet; keep its reply
# only to prove the gap (drawer-contract-retype-gap.json is not a fixture).
bob capture-parse --format json -- 'Postgres 17 minimum @foo+bar#requirements #fix' \
  > "$scratch_root/retype-gap.json"

# --- Synthetic overlays: plan fields Bob does not emit yet ---
# Each overlay edits the real reply for the same draft and nothing else. Row field names
# are those of Bob's `DrawerCandidate` (src/native/capture_complete/model.rs).
python3 - "$fixtures" "$scratch_root/retype-gap.json" "$scratch_root/gaps.md" <<'PY'
import copy
import json
import pathlib
import sys

fixtures = pathlib.Path(sys.argv[1])
retype_gap = json.loads(pathlib.Path(sys.argv[2]).read_text())
gaps_path = pathlib.Path(sys.argv[3])


def load(name):
    return json.loads((fixtures / name).read_text())


def save(name, value):
    (fixtures / name).write_text(json.dumps(value, separators=(", ", ": "), ensure_ascii=False) + "\n")


# What the real fixtures still lack, recorded so the README stays honest.
empty = load("drawer-complete-empty.json")
typed = load("drawer-complete-typed-none.json")
new_capture = load("drawer-capture-new.json")
listing = load("drawer-list.json")
rows = empty["candidates"]
gaps = []
if empty.get("initial_selection") != "none":
    gaps.append("`initial_selection: none` on an empty `@route+id#` query")
if {row.get("group") for row in rows} & {"recent", "new"} == set():
    gaps.append("`recent` and `new` rows in `capture-complete` (a typed name with no match returns no rows)")
if not any(row.get("detail") for row in rows):
    gaps.append("`detail` copy on drawer rows (`3 notes`)")
if not any(row.get("consequence") for row in rows):
    gaps.append("`consequence` footer copy on drawer rows")
if not any(row.get("refused") for row in rows + typed["candidates"]):
    gaps.append("`refused` reasons for reserved or near-duplicate names")
if "drawer" not in new_capture:
    gaps.append("the per-item `drawer: {title, key, created}` object (only `parent_section`)")
if any(d.get("code") == "type_marker_not_applicable" for d in retype_gap.get("diagnostics", [])):
    gaps.append("a separate `#type` retype beside a drawer (`type_marker_not_applicable`)")
gaps_path.write_text("".join(f"- {gap}\n" for gap in gaps))

# The plan's `replacement` covers the glued `#` and the name, so every contract
# response starts its range at the `#` (column 28 in these drafts), and each row's
# `replacement` and `cursor_after` follow from that. Real Bob still starts after the `#`.
HASH = 28


def cover_hash(response):
    response["replacement"] = {"start": HASH, "end": response["replacement"]["end"]}
    return response


def row_for(title, group, **extra):
    slug = title.lower().replace(" ", "-")
    replacement = f"#{slug}"
    row = {
        "replacement": replacement,
        "title": title,
        "key": title,
        "slug": slug,
        "route": "foo",
        "block_id": "bar",
        "text": "Upgrade Postgres",
        "line": 0,
        "entry_count": 0,
        "group": group,
        "detail": "",
        "creates": group != "task",
        "cursor_after": HASH + len(replacement),
    }
    row.update(extra)
    return row


# 1. Empty query: task rows, Recent rows, and the unselected open.
overlay = cover_hash(copy.deepcopy(empty))
overlay["initial_selection"] = "none"
task_rows = overlay["candidates"]
for row, detail, consequence in zip(
    task_rows,
    ["3 notes", "1 note"],
    ['Adds after "fast disk" in REQUIREMENTS', 'Adds after "sharding" in FUTURE WORK'],
):
    row["replacement"] = f"#{row['slug']}"
    row["cursor_after"] = HASH + len(row["replacement"])
    row["group"] = "task"
    row["detail"] = detail
    row["consequence"] = consequence
recent = [
    row_for(
        recent_row["title"],
        "recent",
        note_count=recent_row["note_count"],
        last_seen=recent_row["last_seen"],
        detail=f"used in {recent_row['note_count']} notes · 3 days ago",
        consequence=f"Creates {recent_row['title']} under ^bar",
    )
    for recent_row in listing["recent"]
]
overlay["candidates"] = task_rows + recent
save("drawer-contract-complete-empty.json", overlay)

# 2. A typed name with no match: only the New row.
typed_overlay = cover_hash(copy.deepcopy(typed))
typed_overlay["candidates"] = [
    row_for("PERF", "new", consequence="Creates PERF under ^bar"),
]
save("drawer-contract-complete-typed-new.json", typed_overlay)

# 3. A typed name that matches a Recent drawer, followed by its New row.
match = cover_hash(copy.deepcopy(load("drawer-complete-typed-recent.json")))
match["candidates"] = [
    row_for(
        "MOTIVATION",
        "recent",
        note_count=3,
        last_seen=listing["recent"][1]["last_seen"],
        detail="used in 3 notes · 3 days ago",
        consequence="Creates MOTIVATION under ^bar",
    ),
    row_for("MOT", "new", consequence="Creates MOT under ^bar"),
]
save("drawer-contract-complete-typed-recent.json", match)

# 4. A refused row: Bob explains why Return would do nothing.
refused = cover_hash(copy.deepcopy(load("drawer-complete-typed-reserved.json")))
refused["candidates"] = [
    row_for(
        "TASKS",
        "new",
        refused="TASKS is reserved for the note's task list",
        consequence="Pick another name",
    ),
]
save("drawer-contract-complete-refused.json", refused)

# 5. The commit preview: the new-drawer capsule and the retype row together.
capture = copy.deepcopy(new_capture)
capture["drawer"] = {"title": "PERF BUDGET", "key": "PERF BUDGET", "created": True}
capture["task_theme"] = {
    "action": "set",
    "theme": {
        "key": "fix",
        "name": "FIX",
        "hue": "blue",
        "hue_source": "config",
        "configured": True,
    },
    "previous": None,
}
save("drawer-contract-capture-new-retype.json", capture)
PY

# Self-checks: every fixture parses, and the real replies keep the shapes the Mac decodes.
python3 - "$fixtures" <<'PY'
import json
import pathlib
import sys

fixtures = pathlib.Path(sys.argv[1])


def load(name):
    return json.loads((fixtures / name).read_text())


for path in sorted(fixtures.glob("drawer-*.json")):
    json.loads(path.read_text())

assert load("drawer-parse-empty.json")["needs"] == ["drawer"]
assert any(span["kind"] == "drawer" for span in load("drawer-parse-new.json")["spans"])
assert load("drawer-parse-new.json")["grammar"] >= 3
empty = load("drawer-complete-empty.json")
assert empty["context"] == "drawer" and empty["target"]["block_id"] == "bar"
assert [row["title"] for row in empty["candidates"]] == ["REQUIREMENTS", "FUTURE WORK"]
assert load("drawer-complete-plain-task.json")["candidates"] == []
missing = load("drawer-complete-missing-target.json")
assert missing["candidates"] == [] and missing["warnings"]
assert load("drawer-capture-existing.json")["parent_section"] == "REQUIREMENTS"
assert load("drawer-capture-new.json")["parent_section"] == "PERF BUDGET"
assert "parent_section" not in load("drawer-capture-plain-child.json")
assert load("drawer-list.json")["count"] == 2
assert load("drawer-list-empty.json")["count"] == 0
contract = load("drawer-contract-complete-empty.json")
assert contract["initial_selection"] == "none"
assert [row["group"] for row in contract["candidates"]] == ["task", "task", "recent", "recent"]
assert load("drawer-contract-complete-refused.json")["candidates"][0]["refused"]
assert load("drawer-contract-capture-new-retype.json")["drawer"]["created"] is True
for name in (
    "drawer-contract-complete-empty.json",
    "drawer-contract-complete-typed-new.json",
    "drawer-contract-complete-typed-recent.json",
    "drawer-contract-complete-refused.json",
):
    response = load(name)
    assert response["replacement"]["start"] == 28, name
    assert all(row["replacement"].startswith("#") for row in response["candidates"]), name
PY

{
  echo "# Drawer fixtures"
  echo
  echo "Generated by \`Scripts/generate-drawer-fixtures.sh\`:"
  echo
  echo '```bash'
  echo 'BOB_BIN=/path/to/bob-cli/target/debug/bob BOB_CLI_DIR=/path/to/bob-cli \'
  echo '  Scripts/generate-drawer-fixtures.sh'
  echo '```'
  echo
  echo "Generated with \`${version_line}\` built from bob-cli revision \`${cli_revision}\`"
  echo "(grammar revision 3, \`schema_version\` 1). The script refuses a binary that reports a"
  echo "lower grammar, a bob-cli checkout without \`${prerequisite_commit}\`, or a dirty checkout."
  echo
  echo "Inputs are fully isolated: a scratch vault (\`foo.md\` with task \`^bar\` holding"
  echo "REQUIREMENTS and FUTURE WORK drawers and a drawer-less \`^plain\`, plus \`other1-3.md\`,"
  echo "which each use MOTIVATION and ACCEPTANCE so both rank as Recent), the Tasks plugin"
  echo "status settings, a config with BUILD, FIX, and WRITE types, a daily note with one"
  echo "running FIX Pomodoro, a cleared environment, and \`BOB_NOW=2026-10-30 09:15:00\`."
  echo "Every capture is a dry run with \`--no-clip\`. Only the scratch root in Bob's output is"
  echo "rewritten (to \`${stable_root}\`)."
  echo
  echo "## Real fixtures"
  echo
  echo "Raw Bob replies, unedited apart from the scratch path."
  echo
  cat "$manifest"
  echo
  echo "## Synthetic contract fixtures"
  echo
  echo "Bob at this revision does not emit the whole drawer menu contract. The files named"
  echo "\`drawer-contract-*.json\` are the real reply for the same draft with only the missing"
  echo "fields overlaid, using the row field names of Bob's \`DrawerCandidate\` and the plan's"
  echo "\`replacement\` that covers the glued \`#\` and the name. They exist so"
  echo "the Recent, New, refused, consequence, unselected-open, and new-drawer-preview"
  echo "behaviors have tests; they are not Bob output. Fields this Bob still omits:"
  echo
  cat "$scratch_root/gaps.md"
  echo
  echo "| Fixture | Real reply it overlays |"
  echo "| --- | --- |"
  echo "| \`drawer-contract-complete-empty.json\` | \`drawer-complete-empty.json\` plus \`initial_selection: none\`, \`group: task\`, \`detail\`, \`consequence\`, \`#\`-covering \`replacement\` ranges, and two Recent rows from \`drawer-list.json\` |"
  echo "| \`drawer-contract-complete-typed-new.json\` | \`drawer-complete-typed-none.json\` plus the New row |"
  echo "| \`drawer-contract-complete-typed-recent.json\` | \`drawer-complete-typed-recent.json\` plus a Recent row and the New row |"
  echo "| \`drawer-contract-complete-refused.json\` | \`drawer-complete-typed-reserved.json\` plus a refused New row |"
  echo "| \`drawer-contract-capture-new-retype.json\` | \`drawer-capture-new.json\` plus \`drawer\` (\`created: true\`) and \`task_theme\` |"
} > "$fixtures/drawer-fixtures-README.md"

echo "Generated drawer fixtures with ${version_line} (bob-cli ${cli_revision})"

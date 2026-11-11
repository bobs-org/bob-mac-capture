#!/usr/bin/env bash
# Generate notebook capture and completion fixtures from a Bob binary built
# from a clean bob-cli checkout. Every command uses isolated XDG paths and a
# scratch vault.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bob_bin="$(printenv BOB_BIN || true)"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a Bob binary built from BOB_CLI_DIR." >&2
  exit 1
fi
cli_dir="$(printenv BOB_CLI_DIR || true)"
if [[ -z "$cli_dir" ]] || ! git -C "$cli_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Set BOB_CLI_DIR to the clean bob-cli checkout used to build BOB_BIN." >&2
  exit 1
fi
if [[ -n "$(git -C "$cli_dir" status --porcelain)" ]]; then
  echo "BOB_CLI_DIR has uncommitted changes; build and record a clean revision." >&2
  exit 1
fi
bob_commit="$(git -C "$cli_dir" rev-parse HEAD)"
if [[ -n "${BOB_COMMIT:-}" && "$BOB_COMMIT" != "$bob_commit" ]]; then
  echo "BOB_COMMIT does not match the clean BOB_CLI_DIR revision." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-notebook-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-notebook-fixture"
fixtures="$repo_root/Tests/Fixtures"
vault="$scratch_root/vault"
config="$scratch_root/config.yml"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache" "$vault"
touch "$config"
NOW="2026-11-10 09:00:00"

bob() {
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$config" \
    BOB_DIR="$vault" \
    BOB_NOW="$NOW" \
    BOB_GMAIL_KICK=off \
    BOB_REF_JOBS_KICK=off \
    TZ=UTC0 \
    "$bob_bin" "$@"
}

assert_json() {
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$fixtures/$1"
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

cursor_of() {
  printf '%s' "$1" | wc -c | tr -d '[:space:]'
}

run_parse() {
  local draft="$1" out="$2"
  bob capture-parse --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

run_complete() {
  local draft="$1" out="$2"
  local cursor
  cursor="$(cursor_of "$draft")"
  bob capture-complete --cursor "$cursor" --format json -- "$draft" \
    > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

run_capture() {
  local draft="$1" out="$2"
  local status=0
  bob capture --bob-dir "$vault" --format json --dry-run -- "$draft" \
    > "$scratch_root/raw.json" || status=$?
  if [[ "$status" != 0 ]]; then
    cat "$scratch_root/raw.json" >&2
    return "$status"
  fi
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

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

cat > "$vault/dev.md" <<'MD'
---
type: "[[area]]"
---
# Developer Tools

## Tasks

## Notebooks

> [!notebooks]
>
> - **[[dev_nvim|Neovim]]** — Neovim configuration and plugin notes.
MD

cat > "$vault/dev_nvim.md" <<'MD'
---
parent: "[[dev]]"
template: "[[new_notebook]]"
type: "[[notebook]]"
summary: Neovim configuration and plugin notes.
created: 2026-11-10T09:00:00-05:00
---

# Neovim

## Setup

- Existing guide [created::2026-11-10] ^existing-guide
- Unidentified guide [created::2026-11-10]
MD

cat > "$vault/dev_nvim_lua.md" <<'MD'
---
parent: "[[dev_nvim]]"
template: "[[new_notebook]]"
type: "[[notebook]]"
summary: Lua snippets for the Neovim configuration.
created: 2026-11-10T09:00:00-05:00
---

# Lua

## Basics

- Lua basics [created::2026-11-10] ^lua-basics
MD

cat > "$vault/dev_empty.md" <<'MD'
---
parent: "[[dev]]"
template: "[[new_notebook]]"
type: "[[notebook]]"
created: 2026-11-10T09:00:00-05:00
---

# Empty notebook
MD

cat > "$vault/dev_dup.md" <<'MD'
---
parent: "[[dev]]"
template: "[[new_notebook]]"
type: "[[notebook]]"
created: 2026-11-10T09:00:00-05:00
---

# Duplicate sections

## Git

- First copy [created::2026-11-10]

## Git

- Second copy [created::2026-11-10]
MD

# Completion responses exercise notebook routes, sections, IDs, and the
# notebook-only + picker, including an ID-less note that needs Bob's ID flow.
run_complete "@dev_" notebook-complete-route.json
run_complete "@dev_nvim+" notebook-complete-parent-notes.json
run_complete "@dev_nvim#" notebook-complete-sections.json
run_complete "@dev_nvim^" notebook-complete-block-id.json
run_complete "Notes @dev^new@ %" notebook-complete-create-directive.json
run_parse "Fresh setup @dev_nvim#Setup^fresh-entry" notebook-parse-named-section-note.json
run_parse "Child note @dev_nvim+existing-guide" notebook-parse-sub-note.json
run_parse "More @dev_nvim#" notebook-parse-section-glued.json
run_parse $'@dev_nvim\n- #' notebook-parse-section-bullet-empty.json
run_parse $'@dev_empty\n- #' notebook-parse-section-empty.json
run_parse $'@dev_nvim\n- #Setup' notebook-parse-section-bullet-existing.json
run_parse $'@dev_nvim\n- #wireguard' notebook-parse-section-bullet-clean-create.json
run_parse $'@dev_nvim\n- #Setp' notebook-parse-section-bullet-near-miss.json
run_parse $'@dev_nvim\n- #wireguard\n  - Set up tunnel\n- #Wir' notebook-parse-section-bullet-draft.json
run_parse $'@dev_dup\n- #git' notebook-parse-section-bullet-refused.json
run_parse $'Nvim notes @dev^nvim@ %n\n- KEYMAPS\n  - x\n- #key' \
  notebook-parse-section-bullet-staged-create.json

# Grammar 26 place-menu coverage: glued and bullet sections, empty destinations,
# existing/draft/new rows, clean and near-miss creation, and a refused duplicate.
run_parse "@dev_empty#" notebook-parse-section-glued-empty.json
run_complete "More @dev_nvim#" notebook-complete-section-glued.json
run_complete "@dev_empty#" notebook-complete-section-glued-empty.json
run_complete $'@dev_nvim\n- #' notebook-complete-section-bullet-empty.json
run_complete $'@dev_empty\n- #' notebook-complete-section-empty.json
run_complete $'@dev_nvim\n- #Setup' notebook-complete-section-bullet-existing.json
run_complete $'@dev_nvim\n- #wireguard' notebook-complete-section-bullet-clean-create.json
run_complete $'@dev_nvim\n- #Setp' notebook-complete-section-bullet-near-miss.json
run_complete $'@dev_nvim\n- #wireguard\n  - Set up tunnel\n- #Wir' \
  notebook-complete-section-bullet-draft.json
run_complete $'@dev_dup\n- #git' notebook-complete-section-bullet-refused.json
run_complete $'Nvim notes @dev^nvim@ %n\n- KEYMAPS\n  - x\n- #key' \
  notebook-complete-section-bullet-staged-create.json

draft='More @dev_nvim/'
cursor="$(cursor_of "$draft")"
bob capture-rewrite --cursor "$cursor" --format json -- "$draft" > "$scratch_root/raw.json"
persist "$scratch_root/raw.json" capture-rewrite-slash-alias-notebook-section.json
assert_json capture-rewrite-slash-alias-notebook-section.json
rewritten="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["text"])' "$fixtures/capture-rewrite-slash-alias-notebook-section.json")"
run_complete "$rewritten" notebook-complete-section-slash-alias.json

# Multiple existing-note operations preserve result order and include an
# existing H2, a created H2, an authored block ID, and child notebook rows.
run_capture 'Fresh setup @dev_nvim#Setup^fresh-entry

Release information @dev_nvim#"Release Notes"

Additional guide details @dev_nvim+existing-guide

Lua snippet details @dev_nvim_lua+lua-basics' notebook-capture-existing-notes.json

run_capture 'First batch note @dev_nvim#Setup^batch-first

Second batch note @dev_nvim#"Batch Notes"^batch-second

Top region note @dev_nvim' \
  notebook-capture-grouped-notes.json

run_capture 'Wireguard setup @dev_nvim#Wireguard^wireguard-setup
- KEYS
  - Rotate tunnel key' \
  notebook-capture-create-section.json

# The first item creates a notebook and its parent catalog entry. The second
# item uses the just-created route, proving same-draft resolution and file
# pairing for action=create by exact relative path.
run_capture 'Keymaps @dev^keys@ %n
- MAPPINGS
  - Leader key basics

Primary leader key @dev_keys#Mappings' \
  notebook-capture-create-then-use.json

# Creating beneath the nested notebook names the immediate parent (Lua),
# not the root owner. The breadcrumb is owner through the new title.
run_capture 'Keymaps @dev_nvim_lua^keys@ %n
- MAPPINGS
  - Leader key basics' \
  notebook-capture-create-nested.json

# A route catalog sample carries the notebook owner, title, summary, and
# ancestry shown by the Mac completion menu.
bob capture-targets --format json > "$scratch_root/raw.json"
persist "$scratch_root/raw.json" notebook-targets.json
assert_json notebook-targets.json

python3 - "$fixtures" <<'PY'
import json
import pathlib
import sys

fixtures = pathlib.Path(sys.argv[1])

def load(name):
    return json.loads((fixtures / name).read_text())

for path in fixtures.glob("notebook-*.json"):
    json.loads(path.read_text())

empty = load("notebook-complete-section-bullet-empty.json")
assert empty["context"] == "notebook_section_bullet"
assert empty["place_menu"]["kind"] == "notebook_section"
assert empty["place_menu"]["empty_hint"] == "Type a section name"
assert empty["initial_selection"] == "none"

no_sections = load("notebook-complete-section-empty.json")
assert no_sections["context"] == "notebook_section_bullet"
assert no_sections["candidates"] == []
assert no_sections["place_menu"]["empty_hint"] == "Type a section name"

glued_empty = load("notebook-complete-section-glued-empty.json")
assert glued_empty["context"] == "section"
assert glued_empty["candidates"] == []

existing = load("notebook-complete-section-bullet-existing.json")
assert existing["candidates"][0]["title"] == "Setup"
assert existing["candidates"][0]["replacement"].endswith("\n  - ")
existing_span = next(
    span for span in load("notebook-parse-section-bullet-existing.json")["spans"]
    if span["kind"] == "section"
)
assert existing_span["notebook"] is True and existing_span["section_action"] == "existing"

clean = load("notebook-complete-section-bullet-clean-create.json")
assert len(clean["candidates"]) == 1
assert clean["candidates"][0]["group"] == "new"
assert clean["candidates"][0]["creates"] is True
assert clean.get("initial_selection") is None
create_span = next(
    span for span in load("notebook-parse-section-bullet-clean-create.json")["spans"]
    if span["kind"] == "section"
)
assert create_span["notebook"] is True and create_span["section_action"] == "create"

near_miss = load("notebook-complete-section-bullet-near-miss.json")
assert near_miss["initial_selection"] == "none"
assert "did you mean" in near_miss["candidates"][-1]["detail"]

draft = load("notebook-complete-section-bullet-draft.json")
assert any(row.get("group") == "draft" for row in draft["candidates"])

refused = load("notebook-complete-section-bullet-refused.json")
assert refused["initial_selection"] == "none"
assert all(row.get("refused") for row in refused["candidates"])

rewrite = load("capture-rewrite-slash-alias-notebook-section.json")
assert rewrite["text"] == "More @dev_nvim#"
assert rewrite["alias"]["id"] == "hash_menu"
assert load("notebook-complete-section-slash-alias.json")["place_menu"] == load(
    "notebook-complete-section-glued.json"
)["place_menu"]
assert load("notebook-complete-section-glued.json")["candidates"][0]["replacement"] == "Setup"

batch = load("notebook-capture-grouped-notes.json")["captures"]
assert len(batch) == 3 and all(item["kind"] == "notebook_note" for item in batch)
assert [item["notebook"].get("section") for item in batch] == [
    "Setup",
    "Batch Notes",
    None,
]
assert [item["notebook"].get("section_action") for item in batch] == [
    "existing",
    "create",
    None,
]
assert len({item["notebook"]["route"] for item in batch}) == 1

created = load("notebook-capture-create-section.json")
created_item = created["captures"][0] if "captures" in created else created
assert created_item["notebook"]["section_action"] == "create"
PY

{
  echo "# Notebook fixtures"
  echo
  echo "Generated from a real Bob; do not hand-edit the JSON."
  echo
  echo '```bash'
  echo 'BOB_BIN=/path/to/CARGO_TARGET_DIR/debug/bob BOB_CLI_DIR=/path/to/bob-cli \'
  echo '  Scripts/generate-notebook-fixtures.sh'
  echo '```'
  echo
  echo "- bob: $bob_commit"
  echo "- clock: $NOW, TZ=UTC0, isolated XDG paths, scratch vault only"
  echo "- vault: area dev; notebook frontmatter and owner catalog follow the"
  echo "  notebooks contract; dev_nvim and nested dev_nvim_lua contain one"
  echo "  block-ID note and one ID-less note; dev_empty has no sections and dev_dup"
  echo "  has two identically named sections"
  echo "- commands: capture-complete (notebook route, parent notes, sections, block"
  echo "  ID, create directive, glued and bullet section menus including empty,"
  echo "  existing, staged, new, clean-create, near-miss, refused, and glued-empty"
  echo "  rows); capture-parse (ordinary, sub-notes, glued empty, and notebook"
  echo "  section bullets); capture-rewrite (slash alias); capture --dry-run"
  echo "  (existing/new/top sections, named note, child notes, grouped notebook"
  echo "  batch, create-then-use batch, nested creation); capture-targets"
} > "$fixtures/notebook-fixtures-README.md"

echo "Generated notebook fixtures with $bob_commit"

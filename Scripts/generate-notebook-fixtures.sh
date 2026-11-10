#!/usr/bin/env bash
# Generate notebook capture and completion fixtures from a landed Bob binary.
# Every Bob command uses isolated XDG paths and a scratch vault.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bob_bin="$(printenv BOB_BIN || true)"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a Bob binary that supports notebook capture." >&2
  exit 1
fi
bob_commit="$(printenv BOB_COMMIT || true)"
if [[ -z "$bob_commit" ]]; then
  bob_commit="$("$bob_bin" --version 2>/dev/null | head -n 1 || echo unknown)"
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

# Completion responses exercise notebook routes, sections, IDs, and the
# notebook-only + picker, including an ID-less note that needs Bob's ID flow.
run_complete "@dev_" notebook-complete-route.json
run_complete "@dev_nvim+" notebook-complete-parent-notes.json
run_complete "@dev_nvim#" notebook-complete-sections.json
run_complete "@dev_nvim^" notebook-complete-block-id.json
run_complete "Notes @dev^new@ %" notebook-complete-create-directive.json
run_parse "Fresh setup @dev_nvim#Setup^fresh-entry" notebook-parse-named-section-note.json
run_parse "Child note @dev_nvim+existing-guide" notebook-parse-sub-note.json

# Multiple existing-note operations preserve result order and include an
# existing H2, a created H2, an authored block ID, and child notebook rows.
run_capture 'Fresh setup @dev_nvim#Setup^fresh-entry

Release information @dev_nvim#"Release Notes"

Additional guide details @dev_nvim+existing-guide

Lua snippet details @dev_nvim_lua+lua-basics' notebook-capture-existing-notes.json

# The first item creates a notebook and its parent catalog entry. The second
# item uses the just-created route, proving same-draft resolution and file
# pairing for action=create by exact relative path.
run_capture 'Keymaps @dev^keys@ %n
- MAPPINGS
  - Leader key basics

Primary leader key @dev_keys#Mappings' \
  notebook-capture-create-then-use.json

# A route catalog sample carries the notebook owner, title, summary, and
# ancestry shown by the Mac completion menu.
bob capture-targets --format json > "$scratch_root/raw.json"
persist "$scratch_root/raw.json" notebook-targets.json
assert_json notebook-targets.json

cat > "$fixtures/notebook-fixtures-README.md" <<EOF
# Notebook fixtures

Generated from a real Bob; do not hand-edit the JSON.

- bob: $bob_commit
- clock: $NOW, TZ=UTC0, isolated XDG paths, scratch vault only
- vault: area dev; notebook frontmatter and owner catalog follow the
  notebooks contract; dev_nvim and nested dev_nvim_lua contain one
  block-ID note and one ID-less note
- commands: capture-complete (notebook route, parent notes, sections, block
  ID, create directive); capture-parse (ordinary and sub-notes); capture
  --dry-run (existing section, new section, named note, child notes, and
  create-then-use batch); capture-targets
EOF

echo "Generated notebook fixtures with $bob_commit"

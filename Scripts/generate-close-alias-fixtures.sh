#!/usr/bin/env bash
# Record close-outcome `x`/`s` capture-rewrite fixtures from a built Bob.
#
#   BOB_BIN=/path/to/bob Scripts/generate-close-alias-fixtures.sh
#
# Writes:
#   capture-rewrite-sigil-alias-close-whole.json   `xx` -> `x!`
#   capture-rewrite-sigil-alias-close-park.json    `xs` -> `x*`
#   capture-rewrite-sigil-alias-close-past.json    `x=1=s` -> `x=1=*`
#   capture-rewrite-sigil-alias-close-link.json    `@r:id=xx` -> `@r:id=x!`
#   capture-rewrite-sigil-alias-close-lead.json    `+2 xs` -> `+2 x*`
#   capture-rewrite-sigil-alias-close-numbered.json `x1s` -> `x1*`
#   capture-rewrite-sigil-alias-close-prose.json   `Plan xs` unchanged
#   capture-rewrite-sigil-alias-close-old-bob.json `xx` unchanged (old-bob shape)
#   capture-rewrite-sigil-alias-close-sized-whole.json `2xx` -> `2x!`
#   capture-rewrite-sigil-alias-close-sized-numbered.json `12xs` -> `12x*`
#   capture-rewrite-sigil-alias-close-sized-lead.json `--1 2xx` -> `--1 2x!`
#   capture-rewrite-sigil-alias-close-sized-link.json `^r:id=2xs` -> `^r:id=2x*`
#   capture-rewrite-sigil-alias-close-sized-prose-plan.json `Plan 2xx` unchanged
#   capture-rewrite-sigil-alias-close-sized-prose-made.json `x made 2xx` unchanged
#   capture-rewrite-sigil-alias-close-sized-prose-caps.json `2Xx` unchanged
#
# `capture-rewrite` is pure text, so no vault isolation is needed. The old-bob
# fixture is a hand-written unchanged shape, not Bob output.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi

fixtures="$repo_root/Tests/Fixtures"

# UTF-8 offsets are byte offsets even when the host locale counts characters.
record_rewrite() {
  local name="$1" draft="$2"
  local cursor
  cursor="$(printf '%s' "$draft" | wc -c | tr -d ' ')"
  "$bob_bin" capture-rewrite --cursor "$cursor" --format json -- "$draft" > "$fixtures/capture-rewrite-sigil-alias-close-$name.json"
}
record_rewrite emoji $'Hi 🧪\n\nxx'
record_rewrite chained 'x1*2x'

"$bob_bin" capture-rewrite --cursor 2 --format json -- "xx" > "$fixtures/capture-rewrite-sigil-alias-close-whole.json"
"$bob_bin" capture-rewrite --cursor 2 --format json -- "xs" > "$fixtures/capture-rewrite-sigil-alias-close-park.json"
"$bob_bin" capture-rewrite --cursor 5 --format json -- "x=1=s" > "$fixtures/capture-rewrite-sigil-alias-close-past.json"
"$bob_bin" capture-rewrite --cursor 8 --format json -- "@r:id=xx" > "$fixtures/capture-rewrite-sigil-alias-close-link.json"
"$bob_bin" capture-rewrite --cursor 5 --format json -- "+2 xs" > "$fixtures/capture-rewrite-sigil-alias-close-lead.json"
"$bob_bin" capture-rewrite --cursor 3 --format json -- "x1s" > "$fixtures/capture-rewrite-sigil-alias-close-numbered.json"
"$bob_bin" capture-rewrite --cursor 7 --format json -- "Plan xs" > "$fixtures/capture-rewrite-sigil-alias-close-prose.json"
"$bob_bin" capture-rewrite --cursor 3 --format json -- "2xx" > "$fixtures/capture-rewrite-sigil-alias-close-sized-whole.json"
"$bob_bin" capture-rewrite --cursor 4 --format json -- "12xs" > "$fixtures/capture-rewrite-sigil-alias-close-sized-numbered.json"
"$bob_bin" capture-rewrite --cursor 7 --format json -- "--1 2xx" > "$fixtures/capture-rewrite-sigil-alias-close-sized-lead.json"
"$bob_bin" capture-rewrite --cursor 9 --format json -- "^r:id=2xs" > "$fixtures/capture-rewrite-sigil-alias-close-sized-link.json"
"$bob_bin" capture-rewrite --cursor 8 --format json -- "Plan 2xx" > "$fixtures/capture-rewrite-sigil-alias-close-sized-prose-plan.json"
"$bob_bin" capture-rewrite --cursor 10 --format json -- "x made 2xx" > "$fixtures/capture-rewrite-sigil-alias-close-sized-prose-made.json"
"$bob_bin" capture-rewrite --cursor 3 --format json -- "2Xx" > "$fixtures/capture-rewrite-sigil-alias-close-sized-prose-caps.json"

cat > "$fixtures/capture-rewrite-sigil-alias-close-old-bob.json" <<'JSON'
{"ok":true,"schema_version":1,"input":"xx","text":"xx","changed":false,"cursor":2,"edits":[]}
JSON

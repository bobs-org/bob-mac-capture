#!/usr/bin/env bash
# Generate truthful Record Card fixtures from a landed Bob binary.
# Follows Scripts/generate-task-type-fixtures.sh conventions:
# isolated vault, explicit BOB_BIN (never PATH bob), documented inputs.
#
# Inputs (scratch vault only):
#   records:
#     restaurant (dir eat, label Restaurant, emoji 🍽️, dated_notes true)
#       status: required choices {to_try, liked}
#       category: required suggest
#       location: required suggest
#       companions: link list default [["[[kelly]]"]]
#       visited: date
#       url: url
#     podcast (dir podcasts, label Podcast)
#       status: required choices {to_try, subscribed}
#       category: required suggest
#   vault:
#     eat/nagi.md (Ramen, Clark), eat/ramen_ya.md (Ramen, Westfield),
#       eat/cafe_moo.md (Unicode title "Café Møø"), plus five more
#       restaurants with unique categories so value lists exceed six rows
#     podcasts/techmeme.md, mac_inbox.md, dev.md (area for mixed items)
#     day note 2026/20261030.md, BOB_NOW=2026-10-30 09:00:00
#
# Fixtures cover incomplete, complete, invalid, default, optional-empty,
# explicit stem, Unicode, mixed items, record_field/record_value
# (caret, next-missing first/middle/last, named field), route record rows,
# section record_create rows, capture-targets record rows, and an older-Bob
# fixture is checked in by hand (not generated). Commit operations affect
# only the scratch vault.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (e.g. bob-cli's CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
bob_commit="${BOB_COMMIT:-}"
if [[ -z "$bob_commit" ]]; then
  bob_commit="$("$bob_bin" --version 2>/dev/null || echo unknown)"
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-record-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-record-fixture"
fixtures="$repo_root/Tests/Fixtures"
vault="$scratch_root/vault"
config="$scratch_root/config.yml"
cache="$scratch_root/cache"
NOW="2026-10-30 09:00:00"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$cache"
mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin" "$vault/2026" "$vault/eat" "$vault/podcasts"

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

cat > "$config" <<'YAML'
records:
  restaurant:
    dir: eat
    label: Restaurant
    emoji: "🍽️"
    dated_notes: true
    fields:
      status:
        required: true
        values:
          to_try: "To try"
          liked: "Liked"
      category:
        required: true
        suggest: true
      location:
        required: true
        suggest: true
      companions:
        values: link
        list: true
        default: ["[[kelly]]"]
      visited:
        values: date
      url:
        values: url
  podcast:
    dir: podcasts
    label: Podcast
    emoji: "🎙️"
    fields:
      status:
        required: true
        values:
          to_try: "To try"
          subscribed: "Subscribed"
      category:
        required: true
        suggest: true
YAML

cat > "$vault/mac_inbox.md" <<'MD'
---
type: "[[area]]"
---
# Mac inbox

## Tasks
MD
cat > "$vault/dev.md" <<'MD'
---
type: "[[area]]"
---
# Dev

## Tasks
MD
cat > "$vault/eat/nagi.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Nagi"
status: liked
category: "Ramen"
location: "Clark"
---
# Nagi

## Notes
MD
cat > "$vault/eat/ramen_ya.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Ramen Ya"
status: liked
category: "Ramen"
location: "Westfield"
---
# Ramen Ya

## Notes
MD
cat > "$vault/eat/cafe_moo.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Café Møø"
status: liked
category: "Cafe"
location: "Clark"
---
# Café Møø

## Notes
MD
cat > "$vault/eat/pizza_roma.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Pizza Roma"
status: liked
category: "Pizza"
location: "Clark"
---
# Pizza Roma

## Notes
MD
cat > "$vault/eat/taco_luna.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Taco Luna"
status: liked
category: "Tacos"
location: "Westfield"
---
# Taco Luna

## Notes
MD
cat > "$vault/eat/thai_orchid.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Thai Orchid"
status: liked
category: "Thai"
location: "Clark"
---
# Thai Orchid

## Notes
MD
cat > "$vault/eat/burger_joint.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Burger Joint"
status: liked
category: "Burgers"
location: "Clark"
---
# Burger Joint

## Notes
MD
cat > "$vault/eat/sushi_den.md" <<'MD'
---
parent: "[[eat]]"
type: "[[restaurant]]"
title: "Sushi Den"
status: liked
category: "Sushi"
location: "Westfield"
---
# Sushi Den

## Notes
MD
cat > "$vault/podcasts/techmeme.md" <<'MD'
---
parent: "[[podcasts]]"
type: "[[podcast]]"
title: "Techmeme"
status: subscribed
category: "Tech"
---
# Techmeme
MD
cat > "$vault/2026/20261030.md" <<'MD'
## Pomodoros

- [ ] Current (0900-0930)
MD

bob() {
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$cache" \
    BOB_CONFIG_FILE="$config" \
    BOB_DIR="$vault" \
    BOB_DAY_FILE="$vault/2026/20261030.md" \
    BOB_NOW="$NOW" \
    BOB_REF_JOBS_KICK=off \
    TZ="UTC0" \
    "$bob_bin" "$@"
}

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

run_parse() {
  local draft="$1"
  local out="$2"
  bob capture-parse --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

run_complete() {
  local draft="$1"
  local cursor="$2"
  local out="$3"
  shift 3
  bob capture-complete -b "$vault" --cursor "$cursor" --format json "$@" -- "$draft" \
    > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

run_targets() {
  local out="$1"
  bob capture-targets --format json > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

run_capture_dry() {
  local draft="$1"
  local out="$2"
  bob capture -b "$vault" --format json --dry-run -- "$draft" \
    > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

run_capture_commit() {
  local draft="$1"
  local out="$2"
  bob capture -b "$vault" --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

run_capture_refusal() {
  local draft="$1"
  local out="$2"
  local expected="$3"
  local status=0
  bob capture -b "$vault" --format json --dry-run -- "$draft" \
    > "$scratch_root/raw.json" || status=$?
  if [[ "$status" != "$expected" ]]; then
    echo "capture refusal for $out exited $status (expected $expected):" >&2
    cat "$scratch_root/raw.json" >&2
    exit 1
  fi
  persist "$scratch_root/raw.json" "$out"
  assert_json "$out"
}

cursor_of() {
  printf '%s' "$1" | wc -c
}

# Parse fixtures.
run_parse "Ramen Nagi @eat/" record-parse-incomplete.json
run_parse "Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark" record-parse-complete.json
run_parse "Ramen Nagi @eat/
- status:: nope
- category:: Ramen
- location:: Clark" record-parse-invalid.json
run_parse "Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark
- companions::" record-parse-optional-empty.json
run_parse "Ramen Nagi @eat/^custom-stem" record-parse-explicit-stem.json
run_parse "Café Møø @eat/" record-parse-unicode.json
run_parse "Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark

Fix parser @dev" record-parse-mixed.json
run_parse "Ramen Nagi @eat/^custom-stem
- status:: liked" record-parse-explicit-stem-partial.json
run_parse "Ramen Nagi @eat/
- status:: to_try" record-parse-status-only.json
run_parse "Ramen Nagi @eat/
- status:: liked" record-parse-status-liked.json
run_parse "Ramen Nagi @eat/
- status:: liked
- category:: Ramen" record-parse-status-category.json
run_parse "Ramen Nagi @eat/

Talk Python @podcasts/" record-parse-two-records.json
run_parse "Ramen Nagi @eat/
- " record-parse-field.json
run_parse "Ramen Nagi @eat/
- status:: " record-parse-status-caret.json
run_parse "Ramen Nagi @eat/
- status:: liked
- category:: " record-parse-category-caret.json

# Completion fixtures.
run_complete "@" "$(cursor_of "@")" record-complete-route.json
run_complete "Ramen Nagi @eat/
- " "$(cursor_of "Ramen Nagi @eat/
- ")" record-complete-field.json
run_complete "Ramen Nagi @eat/
- status:: " "$(cursor_of "Ramen Nagi @eat/
- status:: ")" record-complete-value-caret.json
run_complete "Ramen Nagi @eat/" "$(cursor_of "Ramen Nagi @eat/")" record-complete-next-missing-first.json -n
run_complete "Ramen Nagi @eat/
- status:: liked" "$(cursor_of "Ramen Nagi @eat/
- status:: liked")" record-complete-next-missing-middle.json -n
run_complete "Ramen Nagi @eat/
- status:: liked
- category:: Ramen" "$(cursor_of "Ramen Nagi @eat/
- status:: liked
- category:: Ramen")" record-complete-next-missing-last.json -n
run_complete "Ramen Nagi @eat/" "$(cursor_of "Ramen Nagi @eat/")" record-complete-named-visited.json -F visited
run_complete "Ramen Nagi @eat/" "$(cursor_of "Ramen Nagi @eat/")" record-complete-named-status.json -F status
run_complete "@eat#" 5 record-complete-section-create.json
# Ordinary caret-at-create-route complete (no -n): record_target rows.
run_complete "Ramen Nagi @eat/" "$(cursor_of "Ramen Nagi @eat/")" record-complete-target-create.json
# Seven or more category values from the extra restaurants.
run_complete "Ramen Nagi @eat/
- status:: liked
- category:: " "$(cursor_of "Ramen Nagi @eat/
- status:: liked
- category:: ")" record-complete-category-many.json
# Current-value named edit on a complete record.
run_complete "Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark" "$(cursor_of "Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark")" record-complete-named-status-current.json -F status

# Capture fixtures (dry-run previews, one commit, and refusals). The
# commit runs last so its scratch-vault write cannot affect earlier
# fixtures; commit operations affect only the scratch vault.
RICH_RESTAURANT="Café \"Møø\": Ramen! @eat/
- status:: liked
- category:: Ramen
- location:: Clark: Downtown
- companions:: [[kelly|Kel]]
- visited:: 2026-10-29
- First visit was great.
  - Extra chili oil on the side.
- Second note."
run_capture_dry "$RICH_RESTAURANT" record-capture-restaurant.json
run_capture_dry "Talk Python @podcasts/
- status:: subscribed
- category:: Tech" record-capture-podcast.json
run_capture_dry "Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark

Talk Python @podcasts/
- status:: subscribed
- category:: Tech" record-capture-two-records.json
run_capture_dry "Fix parser @dev

Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark" record-capture-mixed.json
run_capture_refusal "Ramen Nagi @eat/
- status:: liked" record-capture-missing.json 2
run_capture_refusal "Ramen Nagi @eat/
- status:: nope
- category:: Ramen
- location:: Clark" record-capture-invalid.json 2
run_capture_dry "Ramen Nagi @eat/
- status:: liked
- category:: Ramen
- location:: Clark
- companions::" record-capture-optional-empty.json
run_capture_commit "$RICH_RESTAURANT" record-capture-restaurant-commit.json

# Targets fixture (record rows with type/emoji/count).
run_targets record-targets.json

# Provenance README (not a test fixture).
cat > "$fixtures/record-fixtures-README.md" <<EOF
# Record fixtures

Generated from a real Bob; never hand-edit the JSON.

- bob: $bob_commit
- config: restaurant (eat, 🍽️) + podcast (podcasts), companions default [[kelly]]
- vault: eat/nagi.md, eat/ramen_ya.md, eat/cafe_moo.md, eat/pizza_roma.md,
  eat/taco_luna.md, eat/thai_orchid.md, eat/burger_joint.md, eat/sushi_den.md,
  podcasts/techmeme.md
- clock: $NOW, TZ=UTC0, isolated XDG dirs, scratch vault only
- command shapes: capture-parse (including field/value caret drafts),
  capture-complete (caret, -n, -F, route, section, create-route
  record_target, 7+ category values, current-value named edit),
  capture --dry-run (restaurant with choice glyphs, aliased link,
  Unicode/quotes/colons, nested notes; podcast with no notes; two
  records; mixed task/record; missing and invalid refusals; explicit
  empty optional), one capture commit, capture-targets

Older-Bob fixtures (no record keys) are checked in by hand:
record-parse-old-bob.json, record-complete-old-bob.json,
record-targets-old-bob.json.
EOF

echo "Generated record fixtures with $($bob_bin --version | head -n 1)"

#!/usr/bin/env bash
# Generate real-Bob relation successor fixtures from an explicitly built bob-cli.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixtures="$repo_root/Tests/Fixtures"
bob_bin="${BOB_BIN:-}"
bob_source="${BOB_SOURCE:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a freshly built bob binary." >&2
  exit 1
fi
if [[ -z "$bob_source" || ! -d "$bob_source/.git" ]]; then
  echo "Set BOB_SOURCE to the opened bob-cli checkout used to build BOB_BIN." >&2
  exit 1
fi
if [[ "$(git -C "$bob_source" branch --show-current)" != "master" ]]; then
  echo "BOB_SOURCE must be on current master." >&2
  exit 1
fi

bob_sha="$(git -C "$bob_source" rev-parse HEAD)"
scratch_root="$(mktemp -d /tmp/bob-mac-capture-relation-successor-fixture.XXXXXX)"
stable_root="/tmp/bob-mac-capture-relation-successor-fixture"
trap 'rm -rf -- "$scratch_root"' EXIT
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
mkdir -p "$fixtures"
: > "$scratch_root/config.yml"

write_settings() {
  local vault="$1"
  mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin"
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
      {"symbol":"?","name":"Blocked","type":"TODO"},
      {"symbol":"/","name":"In Progress","type":"IN_PROGRESS"},
      {"symbol":"-","name":"Canceled","type":"CANCELLED"}
    ]
  }
}
JSON
}

write_config() {
  local extra="${1:-}"
  cat > "$scratch_root/config.yml" <<YAML
relations:
  successor_labels:
    - starts after
$extra
YAML
}

new_vault() {
  local vault="$1"
  mkdir -p "$vault"
  write_settings "$vault"
  cat > "$vault/20261102.md" <<'MD'
## Pomodoros
MD
}

seed_park_vault() {
  local vault="$1"
  new_vault "$vault"
  cat > "$vault/agents.md" <<'MD'
- [ ] #task Prepare evaluation prompt [id:: evaluate] ^evaluate
  - 🪢 **LINKS:** starts after [[agents#^implement]]
- [*] #task Send implementation prompt [id:: implement] ^implement
MD
  cat > "$vault/20261102.md" <<'MD'
## Pomodoros
- [ ] (**0920-0950**) — BUILD
  - [[agents#^implement]]
MD
}

seed_done_vault() {
  local vault="$1"
  new_vault "$vault"
  cat > "$vault/agents.md" <<'MD'
- [ ] #task Prepare evaluation prompt [id:: evaluate] ^evaluate
  - 🪢 **LINKS:** starts after [[agents#^implement]]
- [/] #task Send implementation prompt [id:: implement] ^implement
MD
  cat > "$vault/20261102.md" <<'MD'
## Pomodoros
- [ ] () — BUILD
  - [[agents#^implement]]
MD
}

run_bob() {
  local vault="$1"
  shift
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$scratch_root/config.yml" \
    BOB_DIR="$vault" \
    BOB_DAY_FILE="$vault/20261102.md" \
    BOB_NOW="2026-11-02 09:30:00" \
    TZ="UTC0" \
    "$bob_bin" "$@"
}

capture_to() {
  local vault="$1" output="$2" draft="$3"
  shift 3
  run_bob "$vault" capture -b "$vault" --no-clip --format json "$@" -- "$draft" \
    > "$output" 2> "$output.stderr"
}

complete_to() {
  local vault="$1" output="$2" draft="$3"
  local cursor=${#draft}
  run_bob "$vault" capture-complete --cursor "$cursor" --format json -- "$draft" \
    > "$output"
}

parse_to() {
  local vault="$1" output="$2" draft="$3"
  run_bob "$vault" capture-parse --format json -- "$draft" > "$output"
}

persist() {
  python3 - "$1" "$scratch_root" "$stable_root" "$fixtures/$2" <<'PY'
import pathlib
import sys

source, scratch_root, stable_root, destination = sys.argv[1:]
contents = pathlib.Path(source).read_text().replace(scratch_root, stable_root)
pathlib.Path(destination).write_text(contents)
PY
}

assert_capture() {
  python3 - "$1" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert payload.get("ok") is True, payload
assert payload.get("dry_run") in (True, False), payload
PY
}

# The initial scenarios require the successor label that makes these rows eligible.
write_config

# A parked x* event from a real Bob dry run.
park_vault="$scratch_root/parked-x-star"
seed_park_vault "$park_vault"
capture_to "$park_vault" "$scratch_root/parked-x-star.json" 'x*' --dry-run
python3 - "$scratch_root/parked-x-star.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
rows = payload["pomodoro_close"]["relation_successors"]
assert len(rows) == 1 and rows[0]["relation"]["event"] == "parked", payload
assert payload["pull_in"]["groups"][0]["copy"]["glyph"] == "relation", payload
PY
persist "$scratch_root/parked-x-star.json" relation-successor-parked-x-star.json

# A managed Done event from !note:block-id.
done_vault="$scratch_root/done-bang"
seed_done_vault "$done_vault"
capture_to "$done_vault" "$scratch_root/done-bang.json" '!agents:implement' --dry-run
python3 - "$scratch_root/done-bang.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
rows = payload["task_complete"]["relation_successors"]
assert len(rows) == 1 and rows[0]["relation"]["event"] == "done", payload
PY
persist "$scratch_root/done-bang.json" relation-successor-done-bang.json

# Item-level @route+id! unlink of a Pending task.
toggle_vault="$scratch_root/pending-toggle-unlink"
new_vault "$toggle_vault"
cat > "$toggle_vault/agents.md" <<'MD'
- [ ] #task Prepare evaluation prompt [id:: evaluate] ^evaluate
  - 🪢 **LINKS:** starts after [[agents#^implement]]
- [/] #task Send implementation prompt [id:: implement] ^implement
MD
cat > "$toggle_vault/20261102.md" <<'MD'
## Pomodoros
- [ ] (**0920-0950**) — BUILD
  - [[agents#^implement]]
MD
capture_to "$toggle_vault" "$scratch_root/pending-toggle-unlink.json" '@agents+implement!' --dry-run
python3 - "$scratch_root/pending-toggle-unlink.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert payload["kind"] == "task_toggle" and payload["relation_check"] == "checked", payload
assert len(payload["relation_successors"]) == 1, payload
PY
persist "$scratch_root/pending-toggle-unlink.json" relation-successor-pending-toggle-unlink.json

# A held-only result: the source is already In Progress when the target parks.
held_vault="$scratch_root/held-only"
new_vault "$held_vault"
cat > "$held_vault/agents.md" <<'MD'
- [/] #task Prepare evaluation prompt [id:: evaluate] ^evaluate
  - 🪢 **LINKS:** starts after [[agents#^implement]]
- [*] #task Send implementation prompt [id:: implement] ^implement
MD
cat > "$held_vault/20261102.md" <<'MD'
## Pomodoros
- [ ] (**0920-0950**) — BUILD
  - [[agents#^implement]]
MD
capture_to "$held_vault" "$scratch_root/held-only.json" 'x*' --dry-run
python3 - "$scratch_root/held-only.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
close = payload["pomodoro_close"]
assert not close.get("relation_successors"), payload
assert close["relation_held"][0]["reason"] == "already_started", payload
PY
persist "$scratch_root/held-only.json" relation-successor-held-only.json

# Mixed x*!2 explicitly seeds both a hand-off dependency and a relation offer.
mixed_vault="$scratch_root/mixed-x-star-dependency"
new_vault "$mixed_vault"
cat > "$mixed_vault/agents.md" <<'MD'
- [ ] #task Prepare evaluation prompt [id:: evaluate] ^evaluate
  - 🪢 **LINKS:** starts after [[agents#^implement]]
- [*] #task Send implementation prompt [id:: implement] ^implement
- [ ] #task Ship schema change [id:: schema] ^schema
- [?] #task Announce schema change [dependsOn:: schema] [id:: schema-change] ^schema-change
MD
cat > "$mixed_vault/20261102.md" <<'MD'
## Pomodoros
- [ ] (**0920-0950**) — BUILD
  - [[agents#^implement]]
  - [[agents#^schema]]
MD
capture_to "$mixed_vault" "$scratch_root/mixed-x-star-dependency.json" 'x*!2' --dry-run
python3 - "$scratch_root/mixed-x-star-dependency.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
close = payload["pomodoro_close"]
assert close["unblocked"] and close["unblocked"][0]["offer"]["group"] == "hand_off", payload
assert close["relation_successors"] and close["relation_successors"][0]["offer"]["group"] == "relation", payload
assert payload["pull_in"]["offer_count"] == 2, payload
PY
persist "$scratch_root/mixed-x-star-dependency.json" relation-successor-mixed-x-star-dependency.json

# Nested complete-label Done has its own task_complete successor summary.
nested_vault="$scratch_root/nested-complete-label"
seed_done_vault "$nested_vault"
cat > "$nested_vault/done_by.md" <<'MD'
- [ ] #task Close the loop ^close-loop
MD
cat > "$scratch_root/config.yml" <<'YAML'
relations:
  complete_labels:
    - implemented by
  successor_labels:
    - starts after
YAML
capture_to "$nested_vault" "$scratch_root/nested-complete-label.json" \
  '@agents+implement ~done_by:close-loop|"implemented by"' --dry-run
python3 - "$scratch_root/nested-complete-label.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
nested = payload["relation_completes"][0]["task_complete"]
assert nested["relation_check"] == "checked" and nested["relation_successors"], payload
PY
persist "$scratch_root/nested-complete-label.json" relation-successor-nested-complete-label.json
write_config

# A selected-row fixture produced by an opaque key returned by Bob. This is
# intentionally a distinct scratch vault from refusal and -p none below.
selected_vault="$scratch_root/selected-opaque-key"
seed_park_vault "$selected_vault"
capture_to "$selected_vault" "$scratch_root/selection-preview.json" 'x*' --dry-run
opaque_key="$(python3 - "$scratch_root/selection-preview.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(payload["pomodoro_close"]["relation_successors"][0]["offer"]["key"])
PY
)"
capture_to "$selected_vault" "$scratch_root/selected-opaque-key.json" 'x*' -p "$opaque_key"
python3 - "$scratch_root/selected-opaque-key.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
row = payload["pomodoro_close"]["relation_successors"][0]
assert row["offer"]["selected"] is True, payload
assert any(block.get("roles") == ["relation_successor"] for block in payload["task_blocks"]), payload
PY
persist "$scratch_root/selected-opaque-key.json" relation-successor-selected-opaque-key.json

# Required-choice refusal is write-free and saved as a real failure response.
refusal_vault="$scratch_root/required-choice-refusal"
seed_park_vault "$refusal_vault"
python3 - "$refusal_vault" "$scratch_root/before-refusal" <<'PY'
import hashlib, pathlib, sys
root, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
items = sorted((p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest())
               for p in root.rglob("*") if p.is_file())
output.write_text(repr(items))
PY
set +e
capture_to "$refusal_vault" "$scratch_root/required-choice-refusal.json" 'x*' --require-pull-in-choice
refusal_status=$?
set -e
if [[ "$refusal_status" -eq 0 ]]; then
  echo "Expected --require-pull-in-choice to refuse the unpicked relation offer." >&2
  exit 1
fi
python3 - "$refusal_vault" "$scratch_root/before-refusal" "$scratch_root/required-choice-refusal.json" <<'PY'
import hashlib, json, pathlib, sys
root, before_path, response_path = map(pathlib.Path, sys.argv[1:])
after = sorted((p.relative_to(root).as_posix(), hashlib.sha256(p.read_bytes()).hexdigest())
               for p in root.rglob("*") if p.is_file())
assert repr(after) == before_path.read_text(), "required-choice refusal changed scratch-vault bytes"
response = json.loads(response_path.read_text())
assert response.get("ok") is False and response.get("code") == "pull_in_choice_required", response
assert response.get("offers"), response
PY
persist "$scratch_root/required-choice-refusal.json" relation-successor-required-choice-refusal.json

# Explicit none choice on another scratch vault.
none_vault="$scratch_root/none-choice"
seed_park_vault "$none_vault"
capture_to "$none_vault" "$scratch_root/none-choice.json" 'x*' -p none
python3 - "$scratch_root/none-choice.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
row = payload["pomodoro_close"]["relation_successors"][0]
assert payload["pull_in"]["choice"] == "none", payload
assert row["offer"]["selected"] is False, payload
PY
persist "$scratch_root/none-choice.json" relation-successor-none-choice.json

# Bob-authored offers, released-target caveats, and inverse hints.
author_vault="$scratch_root/authoring"
new_vault "$author_vault"
cat > "$author_vault/agents.md" <<'MD'
- [ ] #task Prepare evaluation prompt [id:: evaluate] ^evaluate
- [ ] #task Send implementation prompt [id:: implement] ^implement
- [/] #task Parked target [id:: parked] ^parked
- [x] #task Closed target [id:: closed] ^closed
MD
write_config
offers_draft='Use this @agents+evaluate ~agents:implement|"starts after"'
complete_to "$author_vault" "$scratch_root/authoring-offers.json" "$offers_draft"
python3 - "$scratch_root/authoring-offers.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert payload["relation_successor"]["verdict"] == "offers", payload
assert any(row.get("offers_source") is True for row in payload["candidates"]), payload
PY
persist "$scratch_root/authoring-offers.json" relation-successor-authoring-offers.json

parked_draft='Use this @agents+evaluate ~agents:parked|"starts after"'
complete_to "$author_vault" "$scratch_root/authoring-already-parked.json" "$parked_draft"
python3 - "$scratch_root/authoring-already-parked.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert payload["relation_successor"]["verdict"] == "already_parked", payload
PY
persist "$scratch_root/authoring-already-parked.json" relation-successor-authoring-already-parked.json

closed_draft='Use this @agents+evaluate ~agents:closed|"starts after"'
complete_to "$author_vault" "$scratch_root/authoring-already-closed.json" "$closed_draft"
python3 - "$scratch_root/authoring-already-closed.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert payload["relation_successor"]["verdict"] == "already_closed", payload
PY
persist "$scratch_root/authoring-already-closed.json" relation-successor-authoring-already-closed.json

inverse_draft='Use this @agents+evaluate ~agents:implement|"starts before"'
complete_to "$author_vault" "$scratch_root/authoring-inverse-hint.json" "$inverse_draft"
python3 - "$scratch_root/authoring-inverse-hint.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
effect = payload["relation_successor"]
assert "hint" in effect and "verdict" not in effect, payload
PY
persist "$scratch_root/authoring-inverse-hint.json" relation-successor-authoring-inverse-hint.json

parse_to "$author_vault" "$scratch_root/authoring-spans.json" "$offers_draft"
python3 - "$scratch_root/authoring-spans.json" <<'PY'
import json, pathlib, sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert any(span.get("offers_source") is True for span in payload["spans"]), payload
PY
persist "$scratch_root/authoring-spans.json" relation-successor-authoring-spans.json

bob_version="$("$bob_bin" --version | head -n 1)"
cat > "$fixtures/relation-successor-provenance.md" <<EOF
# Relation successor fixture provenance

- Bob source SHA: $bob_sha
- Bob binary version: $bob_version
- Generator: Scripts/generate-relation-successor-fixtures.sh
- Build command: CARGO_TARGET_DIR=<isolated-target> cargo build --release --bin bob
- Generator command: BOB_SOURCE=<opened bob-cli master checkout> BOB_BIN=<isolated-target>/release/bob Scripts/generate-relation-successor-fixtures.sh
- Clock: BOB_NOW=2026-11-02 09:30:00, TZ=UTC0
- Vault, config, XDG state, and cache are temporary and isolated for each scenario.
- Fixture transformation: replace only the generated scratch root with $stable_root.

The generator asserts each response's expected relation payload. The mixed x*!2
vault explicitly contains both a dependency hand-off and a relation successor offer.
The required-choice refusal, -p none, and opaque-key selection run against separate
scratch vaults.
EOF

echo "Generated real-Bob relation-successor fixtures from $bob_sha"

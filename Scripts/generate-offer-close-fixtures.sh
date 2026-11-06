#!/usr/bin/env bash
# Generate capture offer-close fixtures from a real bob-cli binary.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a bob-cli binary with the offer-verdict flags (for example bob-cli's target/debug/bob)." >&2
  exit 1
fi
bob_version="$("$bob_bin" --version | head -n 1)"

scratch_root="$(mktemp -d /tmp/bob-mac-capture-offer-close-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-offer-close-fixture"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
: > "$scratch_root/config.yml"

new_vault() {
  local vault="$1"
  mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin"
  cat > "$vault/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'EOF'
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
      {"symbol":"-","name":"Cancelled","type":"CANCELLED"}
    ]
  }
}
EOF
  cat > "$vault/sase.md" <<'EOF'
- [ ] #task Bar [id:: bar] ^bar
EOF
  cat > "$vault/deps.md" <<'EOF'
- [?] #task Alpha [dependsOn:: bar] [id:: alpha] ^alpha
- [?] #task Beta [dependsOn:: bar] [id:: beta] ^beta
- [?] #task Gamma [dependsOn:: alpha] [id:: gamma] ^gamma
EOF
  cat > "$vault/20261005.md" <<'EOF'
## Pomodoros
- [ ] (**0920-0950**) — CAPTURE
- [ ] () — FIX
  - [[sase#^bar]]
EOF
}

new_task_vault() {
  local vault="$1"
  mkdir -p "$vault/.obsidian/plugins/obsidian-tasks-plugin"
  cat > "$vault/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'EOF'
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
      {"symbol":"-","name":"Cancelled","type":"CANCELLED"}
    ]
  }
}
EOF
  cat > "$vault/cash.md" <<'EOF'
---
type: "[[area]]"
---
# Cash
EOF
  cat > "$vault/20261005.md" <<'EOF'
## Pomodoros
- [ ] (**0920-0950**) — CAPTURE
- [ ] () — FIX
EOF
}

run_capture() {
  local vault="$1"
  local output="$2"
  shift 2
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$scratch_root/config.yml" \
    BOB_DIR="$vault" \
    BOB_DAY_FILE="$vault/20261005.md" \
    BOB_NOW="2026-10-05 09:30:00" \
    TZ="UTC0" \
    "$bob_bin" capture -b "$vault" --no-clip --format json "$@" > "$output" 2>"$output.stderr"
}

persist() {
  python3 - "$1" "$scratch_root" "$stable_root" "$repo_root/Tests/Fixtures/$2" <<'PY'
import pathlib
import sys

source, scratch_root, stable_root, destination = sys.argv[1:]
pathlib.Path(destination).write_text(
    pathlib.Path(source).read_text().replace(scratch_root, stable_root)
)
PY
}

preview_vault="$scratch_root/preview-vault"
new_vault "$preview_vault"
run_capture "$preview_vault" "$scratch_root/preview.json" --dry-run -- '!sase:bar'
persist "$scratch_root/preview.json" capture-offer-close-preview.json

write_vault="$scratch_root/write-vault"
new_vault "$write_vault"
run_capture "$write_vault" "$scratch_root/write.json" --complete-offer 1 -- '!sase:bar'
persist "$scratch_root/write.json" capture-offer-close-write.json

stale_vault="$scratch_root/stale-vault"
new_vault "$stale_vault"
if run_capture "$stale_vault" "$scratch_root/stale.json" --complete-offer missing -- '!sase:bar'; then
  echo "Expected the stale offer key to be refused" >&2
  exit 1
fi
persist "$scratch_root/stale.json" capture-offer-close-stale.json

conflict_vault="$scratch_root/conflict-vault"
new_vault "$conflict_vault"
if run_capture "$conflict_vault" "$scratch_root/conflict.json" --pull-in 1 --complete-offer 1 -- '!sase:bar'; then
  echo "Expected the conflicting verdict to be refused" >&2
  exit 1
fi
persist "$scratch_root/conflict.json" capture-offer-close-conflict.json

refused_vault="$scratch_root/refused-vault"
new_task_vault "$refused_vault"
new_task_draft=$'Finish packet @cash:pkt@\n- Draft memo\n- Collect docs\n'
if run_capture "$refused_vault" "$scratch_root/refused.json" --complete-offer 1 -- "$new_task_draft"; then
  echo "Expected the new-task offer to be refused" >&2
  exit 1
fi
persist "$scratch_root/refused.json" capture-offer-close-refused.json

python3 - "$scratch_root/preview.json" "$scratch_root/legacy.json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
payload.pop("offer_closes", None)

def strip_offer_close(value):
    if isinstance(value, dict):
        if "offer_count" in value and "groups" in value:
            value.pop("close", None)
        offer = value.get("offer")
        if isinstance(offer, dict):
            offer.pop("close", None)
            offer.pop("verdict", None)
        for child in value.values():
            strip_offer_close(child)
    elif isinstance(value, list):
        for child in value:
            strip_offer_close(child)

strip_offer_close(payload)
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload, indent=2) + "\n")
PY
persist "$scratch_root/legacy.json" capture-offer-close-legacy.json

python3 - "$scratch_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
expectations = {
    "preview.json": (True, None),
    "write.json": (True, None),
    "stale.json": (False, "offer_close_stale"),
    "conflict.json": (False, "offer_verdict_conflict"),
    "refused.json": (False, "offer_close_refused"),
}
for filename, (ok, code) in expectations.items():
    payload = json.loads((root / filename).read_text())
    assert payload.get("ok") is ok, (filename, payload)
    if code is not None:
        assert payload.get("code") == code, (filename, payload)
assert json.loads((root / "preview.json").read_text())["pull_in"]["close"]["supported"]
assert json.loads((root / "write.json").read_text())["offer_closes"]
PY

cat > "$repo_root/Tests/Fixtures/offer-close-provenance.md" <<EOF
# Offer-close fixture provenance

Generated with Scripts/generate-offer-close-fixtures.sh from:

- Bob binary: supplied through the BOB_BIN environment variable
- Version: $bob_version

capture-offer-close-preview.json is a dry-run with two existing dependent offers and Bob-authored close descriptors. capture-offer-close-write.json is a real Done verdict with the recover-only receipt. The stale-key, new-task refusal, and conflicting-pick payloads are real Bob failures. capture-offer-close-legacy.json is derived from the real preview by removing the additive close fields to model an older Bob response.
EOF

echo "Generated offer-close fixtures with $bob_version"

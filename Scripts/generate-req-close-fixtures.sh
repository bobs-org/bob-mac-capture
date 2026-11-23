#!/usr/bin/env bash
# Generate Bob-owned requirement-card protocol fixtures from a current bob binary.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a bob-cli binary with requirement-close support." >&2
  exit 1
fi
bob_version="$("$bob_bin" --version | head -n 1)"
bob_source_rev="${BOB_SOURCE_REV:-unrecorded}"

scratch_root="$(mktemp -d "$repo_root/.tmp-req-close-fixture.XXXXXX")"
cleanup() {
  python3 - "$scratch_root" <<'PY'
import pathlib
import shutil
import sys

root = pathlib.Path(sys.argv[1]).resolve()
if root.name.startswith(".tmp-req-close-fixture."):
    shutil.rmtree(root, ignore_errors=True)
PY
}
trap cleanup EXIT
mkdir -p "$repo_root/Tests/Fixtures/req_close"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
: > "$scratch_root/config.yml"

new_vault() {
  local vault="$1"
  local include_successor="${2:-false}"
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
- [ ] #task Ship parser [id:: ship] ^ship
	- [ ] Handles empty input
		- [ ] Handles zero bytes
	- [ ] Handles unicode
EOF
  if [[ "$include_successor" == true ]]; then
    cat > "$vault/deps.md" <<'EOF'
- [?] #task Write docs [dependsOn:: ship] [id:: docs] ^docs
EOF
  fi
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
    "$bob_bin" capture -b "$vault" --no-clip --format json "$@" \
    > "$output" 2> "$output.stderr"
}

persist_fixture() {
  python3 - "$1" "$scratch_root" "$repo_root/Tests/Fixtures/$2" <<'PY'
import pathlib
import sys

source, scratch_root, destination = sys.argv[1:]
stable_root = "/tmp/bob-mac-capture-req-close-fixture"
text = pathlib.Path(source).read_text().replace(scratch_root, stable_root)
pathlib.Path(destination).write_text(text)
PY
}

req_vault="$scratch_root/req-only-vault"
new_vault "$req_vault"
run_capture "$req_vault" "$scratch_root/req-preview.json" --dry-run --req-choice -- '!sase:ship'
persist_fixture "$scratch_root/req-preview.json" capture-req-close-preview.json

met_vault="$scratch_root/met-vault"
new_vault "$met_vault"
run_capture "$met_vault" "$scratch_root/met.json" --req-choice -- '!sase:ship'
persist_fixture "$scratch_root/met.json" capture-req-close-met.json

mixed_vault="$scratch_root/mixed-vault"
new_vault "$mixed_vault" true
run_capture "$mixed_vault" "$scratch_root/mixed-preview.json" --dry-run --req-choice -- '!sase:ship'
persist_fixture "$scratch_root/mixed-preview.json" capture-req-close-mixed.json
run_capture "$mixed_vault" "$scratch_root/legacy-current.json" --dry-run --require-pull-in-choice --pull-in none -- '!sase:ship'

write_vault="$scratch_root/write-vault"
new_vault "$write_vault"
req_key="$(python3 - "$scratch_root/req-preview.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1]))
print(payload["pull_in"]["groups"][0]["rows"][0]["offer"]["key"])
PY
)"
run_capture "$write_vault" "$scratch_root/write.json" --req-choice --cancel-offer "$req_key=No longer required" -- '!sase:ship'
persist_fixture "$scratch_root/write.json" capture-req-close-write.json

stale_vault="$scratch_root/stale-vault"
new_vault "$stale_vault"
run_capture "$stale_vault" "$scratch_root/stale-preview.json" --dry-run --req-choice -- '!sase:ship'
stale_key="$(python3 - "$scratch_root/stale-preview.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1]))
print(payload["pull_in"]["groups"][0]["rows"][0]["offer"]["key"])
PY
)"
python3 - "$stale_vault/sase.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace("Handles empty input", "Handles empty input now"))
PY
if run_capture "$stale_vault" "$scratch_root/stale.json" --req-choice --carry "$stale_key" -- '!sase:ship'; then
  echo "Expected stale requirement key to be refused" >&2
  exit 1
fi
persist_fixture "$scratch_root/stale.json" capture-req-close-stale.json

python3 - "$scratch_root/legacy-current.json" "$scratch_root/legacy.json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
payload.pop("req_outcomes", None)
pull_in = payload.get("pull_in")
if isinstance(pull_in, dict):
    pull_in.pop("reqs", None)
    pull_in["groups"] = [
        group for group in pull_in.get("groups", [])
        if group.get("kind", group.get("group")) != "requirements"
    ]
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
PY
persist_fixture "$scratch_root/legacy.json" capture-req-close-legacy.json

python3 - "$scratch_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
preview = json.loads((root / "req-preview.json").read_text())
mixed = json.loads((root / "mixed-preview.json").read_text())
write = json.loads((root / "write.json").read_text())
met = json.loads((root / "met.json").read_text())
stale = json.loads((root / "stale.json").read_text())
legacy = json.loads((root / "legacy.json").read_text())
assert preview["pull_in"]["reqs"]["supported"] is True
assert preview["pull_in"]["groups"][0]["kind"] == "requirements"
assert mixed["pull_in"]["groups"][0]["kind"] == "requirements"
assert any(group["group"] != "requirements" for group in mixed["pull_in"]["groups"])
assert met["req_outcomes"] and all(
    outcome["verdict"] == "met" for outcome in met["req_outcomes"]
)
assert "requirements met" in met["req_outcomes"][0]["message"]
assert any(outcome["verdict"] == "drop" for outcome in write["req_outcomes"])
assert stale["code"] == "req_close_stale" and stale["current"]["groups"]
assert "reqs" not in legacy["pull_in"]
assert all(group.get("kind", group["group"]) != "requirements" for group in legacy["pull_in"]["groups"])
lines = (root / "met-vault" / "sase.md").read_text().splitlines()
assert lines == [
    "- [x] #task Ship parser [id:: ship] ^ship",
    "\t- [ ] Handles empty input",
    "\t\t- [ ] Handles zero bytes",
    "\t- [ ] Handles unicode",
]
PY

python3 - "$repo_root/Tests/Fixtures/req_close-provenance.md" "$bob_version" "$bob_source_rev" <<'PY'
import pathlib
import sys

destination, version, source_rev = sys.argv[1:]
pathlib.Path(destination).write_text(f'''# Requirement close fixture provenance

Generated with `Scripts/generate-req-close-fixtures.sh` from:

- Bob binary: supplied through `BOB_BIN`
- Version: {version}
- bob-cli source revision: `{source_rev}`
- Command: `BOB_SOURCE_REV={source_rev} BOB_BIN=<current bob-cli target/debug/bob> Scripts/generate-req-close-fixtures.sh`

The preview and mixed fixtures are Bob dry runs from disposable synthetic vaults. The Met fixture is a real default-Met close: its receipt reports Met, the owner closes, and all requirement checkboxes remain `[ ]`. The write fixture is a real drop verdict with Bob's receipt. The stale fixture changes the row after its preview and records Bob's write-free `req_close_stale` response with `current.groups`. The legacy fixture uses the current Bob's explicit offer-only handshake, then removes only the additive requirement capability and receipts to model a pre-requirements payload.

`req_close/vectors.json` is copied byte for byte from bob-cli's `tests/fixtures/req_close/vectors.json`; bob-cli owns it. Change the source vectors and contract there first, then copy the file and update this README/provenance.
''')
PY

echo "Generated requirement-close fixtures with $bob_version"

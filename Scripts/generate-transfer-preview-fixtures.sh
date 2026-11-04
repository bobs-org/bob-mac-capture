#!/usr/bin/env bash
# Record the capture `>` transfer payloads and spans from a built Bob.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-transfer-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-transfer-fixture"
fixtures="$repo_root/Tests/Fixtures"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
: > "$scratch_root/config.yml"

bob() {
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$scratch_root/config.yml" \
    BOB_DIR="$1" \
    BOB_DAY_FILE="$1/day.md" \
    BOB_NOW="2026-11-03 09:30:00" \
    TZ="UTC0" \
    "$bob_bin" "${@:2}"
}

persist() {
  python3 - "$1" "$scratch_root" "$stable_root" "$fixtures/$2" <<'PY'
import pathlib
import sys

source, scratch_root, stable_root, destination = sys.argv[1:]
text = pathlib.Path(source).read_text().replace(scratch_root, stable_root)
pathlib.Path(destination).write_text(text)
PY
}

vault="$scratch_root/vault"
mkdir -p "$vault"
cat > "$vault/inbox.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Benchmark logical replication ^bench
  - Try pgbench at 10k TPS
- [ ] #task Cut over prod ^cutover
EOF
cat > "$vault/db.md" <<'EOF'
---
type: "[[area]]"
---
## Tasks
- [ ] #task Upgrade Postgres [priority:: 2] ^upgrade
  - FUTURE WORK
    - Existing idea
EOF
cat > "$vault/referrer.md" <<'EOF'
---
type: "[[area]]"
---
See [[inbox#^bench]] for context.
EOF
cat > "$vault/day.md" <<'EOF'
## Pomodoros

- [ ] Current (0900-0930)
EOF

bob "$vault" capture --dry-run --format json -- '@inbox+bench > @db' \
  > "$scratch_root/move.json"
bob "$vault" capture --dry-run --format json -- '@inbox+bench > @db+upgrade' \
  > "$scratch_root/merge.json"
bob "$vault" capture-parse --format json -- '@inbox+bench > @db' \
  > "$scratch_root/parse-move.json"
bob "$vault" capture-parse --format json -- '@inbox+bench > @db+upgrade' \
  > "$scratch_root/parse-merge.json"
bob "$vault" capture-parse --format json -- '@inbox+bench > @' \
  > "$scratch_root/parse-incomplete.json"

python3 - "$scratch_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
move = json.loads((root / "move.json").read_text())
merge = json.loads((root / "merge.json").read_text())
parse_move = json.loads((root / "parse-move.json").read_text())
parse_merge = json.loads((root / "parse-merge.json").read_text())
parse_incomplete = json.loads((root / "parse-incomplete.json").read_text())
assert move.get("kind") == "task_move" and len(move.get("moves", [])) == 1, move
assert merge.get("kind") == "task_merge" and len(merge.get("merges", [])) == 1, merge
assert parse_move.get("mode") == "task_move", parse_move
assert parse_merge.get("mode") == "task_merge", parse_merge
assert "transfer_destination" in parse_incomplete.get("needs", []), parse_incomplete
for parsed in (parse_move, parse_merge):
    kinds = {span["kind"] for span in parsed.get("spans", [])}
    assert {"transfer_source", "transfer_arrow", "transfer_destination"} <= kinds, parsed
PY

persist "$scratch_root/move.json" capture-transfer-move.json
persist "$scratch_root/merge.json" capture-transfer-merge.json
persist "$scratch_root/parse-move.json" capture-parse-transfer-move.json
persist "$scratch_root/parse-merge.json" capture-parse-transfer-merge.json
persist "$scratch_root/parse-incomplete.json" capture-parse-transfer-incomplete.json
echo "wrote capture transfer fixtures to $fixtures"

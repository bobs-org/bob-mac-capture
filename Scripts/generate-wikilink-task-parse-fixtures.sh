#!/usr/bin/env bash
# Generate truthful wikilink-task parse fixtures from this checkout's built Bob.
# Uses an isolated vault and the same BOB_BIN convention as sibling generators.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (e.g. bob-cli's CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
scratch_root="$(mktemp -d /tmp/bob-wikilink-task-parse-vault.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
mkdir -p "$scratch_root/.obsidian"

parse() {
  local draft="$1"; local out="$2"
  BOB_DIR="$scratch_root" "$bob_bin" capture-parse --format json -- "$draft" \
    > "$repo_root/Tests/Fixtures/$out"
}

parse 'Follow up ((' capture-parse-wikilink-task-open.json
parse 'Follow up ((s' capture-parse-wikilink-task-query.json
parse 'Follow up [[mac_inbox#^inbox-plain]]' capture-parse-wikilink-task-inserted.json

# The additive spans did not exist in older Bob builds. Derive the exact old
# response shape from the generated parse fixture by removing only these new
# span kinds; all other parser output stays the current source's real output.
python3 - \
  "$repo_root/Tests/Fixtures/capture-parse-wikilink-task-open.json" \
  "$repo_root/Tests/Fixtures/capture-parse-wikilink-task-old-bob.json" <<'PY'
import json
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[1:])
data = json.loads(source.read_text())
data["spans"] = [
    span
    for span in data.get("spans", [])
    if not span.get("kind", "").startswith("wikilink_task_")
]
destination.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "Generated wikilink-task parse fixtures with $("$bob_bin" --version | head -n 1)"

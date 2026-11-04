#!/usr/bin/env bash
# Generate the project-note move preview fixtures from a real, freshly built Bob.
#
# Persists, all from isolated vaults and a pinned clock:
#   Tests/Fixtures/move-preview-mv1.json    capture --dry-run, one `^` move
#   Tests/Fixtures/move-preview-mv4.json    capture --dry-run, one `:` move
#   Tests/Fixtures/move-preview-mv5.json    capture --dry-run, offer form
#   Tests/Fixtures/move-preview-mv17.json   capture --dry-run, move hint
# Tests decode these fixtures directly (see
# CaptureProjectNoteMovePresentationTests); fake-bob does not serve them.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-move-preview-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-move-preview-fixture"
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
    BOB_NOW="2026-09-20 14:31:07" \
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

check_range() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import pathlib
import sys

path, draft, field = sys.argv[1], sys.argv[2], sys.argv[3]
reply = json.loads(pathlib.Path(path).read_text())
task = reply["project_note"][field][0]
start, end = task["draft_range"]
token = draft.encode("utf-8")[start:end].decode("utf-8")
assert token == task["sigil"] + task["block_id"], (token, task)
PY
}

# Shared vault for MV1, MV5, and MV17: the WORK entry links one task so MV1
# also exercises the Task Link follows path and repaired_files.
vault="$scratch_root/vault"
mkdir -p "$vault"
cat > "$vault/cash.md" <<'EOF'
---
type: "[[area]]"
---
# Cash
## Tasks
- [ ] #task Collect the equity paperwork ^equity-docs
- [ ] #task Call Morgan Stanley about the 401k ^call-ms
- [ ] #task Renew the passport ^renew-the-passport
- [ ] #task Pay the credit card ^pay-cc
- [ ] #task Plan the handoff
- [x] #task Done task ^done-task
- [ ] #task Hidden task ^hidden-task #hide
- [ ] #task Project task ^prj
EOF
cat > "$vault/day.md" <<'EOF'
## Pomodoros
- [ ] (1330-1400) WORK
  - [[cash#^equity-docs]]
## Daily
EOF

# MV1: one `^` move whose Task Link follows into WORK.
draft_mv1='Finish the exit packet @cash^goog-exit@
- ^equity-docs'
bob "$vault" capture --dry-run --format json -- "$draft_mv1" > "$scratch_root/mv1.json"
python3 - "$scratch_root/mv1.json" <<'PY'
import json
import pathlib
import sys

reply = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert reply.get("ok") is True, reply
note = reply["project_note"]
moved = note["moved_tasks"]
assert len(moved) == 1, note
assert (moved[0]["sigil"], moved[0]["block_id"]) == ("^", "equity-docs"), note
assert "Link follows" in (moved[0].get("detail") or ""), note
summary = note["move_summary"]
assert (summary["parent"], summary["moved"]) == ("cash.md", 1), note
assert note["repaired_files"][0]["link_count"] == 1, note
PY
check_range "$scratch_root/mv1.json" "$draft_mv1" moved_tasks
persist "$scratch_root/mv1.json" move-preview-mv1.json

# MV4: one `:` move that becomes Next and links under ADMIN.
admin_vault="$scratch_root/admin-vault"
mkdir -p "$admin_vault"
cat > "$admin_vault/cash.md" <<'EOF'
---
type: "[[area]]"
---
# Cash
## Tasks
- [ ] #task Ready task ^a
EOF
cat > "$admin_vault/day.md" <<'EOF'
## Pomodoros
- [ ] () — ADMIN
## Daily
EOF
draft_mv4='Project @cash^x@#admin
- :a'
bob "$admin_vault" capture --dry-run --format json -- "$draft_mv4" > "$scratch_root/mv4.json"
python3 - "$scratch_root/mv4.json" <<'PY'
import json
import pathlib
import sys

reply = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert reply.get("ok") is True, reply
note = reply["project_note"]
moved = note["moved_tasks"]
assert len(moved) == 1, note
assert moved[0]["sigil"] == ":", note
assert moved[0]["status_symbol"] == "*", note
assert moved[0]["detail"] == "becomes Next · links under ADMIN", note
assert moved[0]["link"]["block_link"] == "[[cash_x#^a]]", note
PY
check_range "$scratch_root/mv4.json" "$draft_mv4" moved_tasks
persist "$scratch_root/mv4.json" move-preview-mv4.json

# MV5: offer form offers the moved row (with `moved_from`) and the new row.
# `^call-ms` is unlinked today, so it stays offered; `^equity-docs` is
# linked under WORK and would fold into `already_planned`.
draft_mv5='Project @cash:x@
- ^call-ms
- New task'
bob "$vault" capture --dry-run --format json -- "$draft_mv5" > "$scratch_root/mv5.json"
python3 - "$scratch_root/mv5.json" <<'PY'
import json
import pathlib
import sys

reply = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert reply.get("ok") is True, reply
note = reply["project_note"]
assert note.get("form") == "offer", note
successors = note["successors"]
assert len(successors) == 2, note
assert successors[0]["block_id"] == "call-ms", note
assert successors[0]["offer"]["moved_from"] == "cash.md", note
assert not successors[1]["offer"].get("moved_from"), note
assert note["move_summary"]["moved"] == 1, note
PY
persist "$scratch_root/mv5.json" move-preview-mv5.json

# MV17: no move bullets, parent has open tasks -> move hint, no summary.
draft_mv17='Finish the exit @cash^x@'
bob "$vault" capture --dry-run --format json -- "$draft_mv17" > "$scratch_root/mv17.json"
python3 - "$scratch_root/mv17.json" <<'PY'
import json
import pathlib
import sys

reply = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert reply.get("ok") is True, reply
note = reply["project_note"]
assert not note.get("moved_tasks"), note
assert note.get("move_summary") is None, note
hint = note["move_hint"]
assert hint["parent"] == "cash.md" and hint["open_count"] >= 1, note
PY
persist "$scratch_root/mv17.json" move-preview-mv17.json

echo "wrote move preview fixtures to $fixtures"
ls "$fixtures"/move-preview-mv*.json

#!/usr/bin/env bash
# Generate the @route:id@ project-offer fixtures from a real, freshly built Bob.
#
# Persists, all from one isolated vault/config/state and a pinned clock:
#   Tests/Fixtures/project-note-successors.json                capture --dry-run
#   Tests/Fixtures/capture-parse-project-note-offer.json       capture-parse (named offer)
#   Tests/Fixtures/capture-rewrite-project-note-offer-seal.json  @r^id@: -> @r:id@
#   Tests/Fixtures/capture-rewrite-project-note-create-seal.json @r:id@^ -> @r^id@
# Tests/Fixtures/fake-bob serves these files verbatim. The script also verifies
# the choice flow against the same binary: dry-run, a required-choice refusal
# that writes nothing, an explicit Skip (`-p none`), and an explicit pick
# (`-p all`), each in its own scratch vault.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (for example bob-cli's target/debug/bob)." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-project-note-offer-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-project-note-offer-fixture"
fixtures="$repo_root/Tests/Fixtures"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
# An empty config keeps every theme unconfigured, so the parse metadata below
# is the deterministic hash hue rather than anything from the user's setup.
: > "$scratch_root/config.yml"

# Create a scratch vault at the given path.
new_vault() {
  local vault="$1"
  mkdir -p "$vault"
  cat > "$vault/cash.md" <<'EOF'
---
type: "[[area]]"
---
# Cash
EOF
  cat > "$vault/day.md" <<'EOF'
## Pomodoros
- [ ] (1330-1400) Work
EOF
}

# The main vault keeps the stable `/tmp/.../vault` paths the fixtures record.
vault="$scratch_root/vault"
new_vault "$vault"
draft=$'Finish the exit packet @cash:goog-exit@\n- Draft the memo\n- Collect paperwork\n- Call the bank :call-bank\n- Private #hide reminder\n'

bob() {
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$scratch_root/config.yml" \
    BOB_DIR="${bob_dir:-$vault}" \
    BOB_DAY_FILE="${bob_dir:-$vault}/day.md" \
    BOB_NOW="2026-09-20 14:31:07" \
    TZ="UTC0" \
    "$bob_bin" "$@"
}

# Persist one reply with only the unstable scratch paths rewritten.
persist() {
  python3 - "$1" "$scratch_root" "$stable_root" "$fixtures/$2" <<'PY'
import pathlib
import sys

source, scratch_root, stable_root, destination = sys.argv[1:]
text = pathlib.Path(source).read_text().replace(scratch_root, stable_root)
pathlib.Path(destination).write_text(text)
PY
}

# 1. The named offer parse: the real `pomodoro_name.themes` metadata, the
# unwashed name span, and the offer marker spans.
parse_draft='Finish it @cash:goog-exit@#admin'
bob capture-parse --format json -- "$parse_draft" > "$scratch_root/parse.json"
python3 - "$scratch_root/parse.json" <<'PY'
import json
import pathlib
import sys

parsed = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert parsed.get("ok") is True, parsed
assert parsed.get("mode") == "pomodoro_project_note", parsed
spans = parsed.get("spans", [])
marker = next((s for s in spans if s.get("kind") == "project_note_offer_marker"), None)
assert marker is not None and marker.get("project_note") == "offer", parsed
name = next((s for s in spans if s.get("kind") == "pomodoro_name"), None)
assert name is not None and "project_note" not in name, parsed
themes = name.get("themes") or []
assert [t.get("key") for t in themes] == ["admin"], parsed
assert all(t.get("hue") and t.get("hue_source") for t in themes), parsed
PY
persist "$scratch_root/parse.json" capture-parse-project-note-offer.json

# 2. The sealed toggles, with the cursor at the end of the draft as the Mac
# sends it.
rewrite() {
  bob capture-rewrite --cursor "${#1}" --format json -- "$1"
}
rewrite 'Do work @file^id@:' > "$scratch_root/rewrite-offer.json"
rewrite 'Do work @file:id@^' > "$scratch_root/rewrite-create.json"
python3 - "$scratch_root/rewrite-offer.json" "$scratch_root/rewrite-create.json" <<'PY'
import json
import pathlib
import sys

for path, expected in zip(
    sys.argv[1:], ["Do work @file:id@", "Do work @file^id@"]
):
    reply = json.loads(pathlib.Path(path).read_text())
    assert reply.get("changed") is True, reply
    assert reply.get("rule") == "switch_block_id_separator", reply
    assert reply.get("text") == expected, reply
PY
persist "$scratch_root/rewrite-offer.json" capture-rewrite-project-note-offer-seal.json
persist "$scratch_root/rewrite-create.json" capture-rewrite-project-note-create-seal.json

# 3. The capture response consumed by CaptureCore: a preview with no picks.
capture() {
  bob capture -b "${bob_dir:-$vault}" --no-clip --format json "$@" -- "$draft"
}
fixture="$scratch_root/project-note-successors.json"
if ! capture --dry-run > "$fixture" 2> "$scratch_root/dry-run.stderr"; then
  cat "$fixture" "$scratch_root/dry-run.stderr" >&2
  exit 1
fi
persist "$fixture" project-note-successors.json

# Bob must refuse this unchosen request before creating either project note or
# Pomodoro links; the Mac client then re-submits with its explicit picks.
if capture --require-pull-in-choice > "$scratch_root/refusal.json" 2>&1; then
  echo "Expected --require-pull-in-choice to refuse an unpicked project offer." >&2
  exit 1
fi
if [[ -e "$vault/cash_goog_exit.md" ]]; then
  echo "Required-choice refusal wrote the project note." >&2
  exit 1
fi
if grep -q 'goog_exit' "$vault/day.md"; then
  echo "Required-choice refusal linked a task into the day note." >&2
  exit 1
fi
python3 - "$scratch_root/refusal.json" <<'PY'
import pathlib
import sys

message = pathlib.Path(sys.argv[1]).read_text().lower()
assert "pull-in" in message or "pull in" in message, message
PY

# Skip (`-p none`): the project note is created and only the authored colon
# bullet is linked; no offered task is picked.
skip_vault="$scratch_root/skip-vault"
new_vault "$skip_vault"
bob_dir="$skip_vault" capture -p none > "$scratch_root/skip.json"
python3 - "$scratch_root/skip.json" "$skip_vault" <<'PY'
import json
import pathlib
import sys

success_path, vault = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
success = json.loads(success_path.read_text())
assert success.get("ok") is True and success.get("dry_run") is False, success
project = success.get("project_note") or {}
successors = project.get("successors") or []
assert len(successors) == 2, success
assert not any(row.get("offer", {}).get("selected") for row in successors), success
assert all(row.get("block_id") == "" for row in successors), success
links = [row.get("block_id") for row in project.get("task_links", [])]
assert links == ["call-bank"], project
assert (vault / "cash_goog_exit.md").is_file()
day = (vault / "day.md").read_text()
assert "[[cash_goog_exit#^call-bank]]" in day, day
assert "draft-memo" not in day and "collect-paperwork" not in day, day
PY

# Finally exercise the successful commit path in the scratch vault. This is a
# real Bob write, isolated from the user's vault and removed by the exit trap.
capture -p all > "$scratch_root/commit.json"
python3 - "$scratch_root/commit.json" "$vault" <<'PY'
import json
import pathlib
import sys

success_path, vault = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
success = json.loads(success_path.read_text())
assert success.get("ok") is True and success.get("dry_run") is False, success
project = success.get("project_note") or {}
successors = project.get("successors") or []
assert len(successors) == 2 and all(row.get("offer", {}).get("selected") for row in successors), success
links = {row.get("block_id") for row in project.get("task_links", [])}
assert {"call-bank", "draft-memo", "collect-paperwork"} <= links, project
assert (vault / "cash_goog_exit.md").is_file()
assert "[[cash_goog_exit#^draft-memo]]" in (vault / "day.md").read_text()
PY

echo "Generated project-note offer fixtures and verified choice flow with $("$bob_bin" --version | head -n 1)"

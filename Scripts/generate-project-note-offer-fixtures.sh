#!/usr/bin/env bash
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
vault="$scratch_root/vault"
mkdir -p "$vault" "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
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
: > "$scratch_root/config.yml"

draft=$'Finish the exit packet @cash:goog-exit@\n- Draft the memo\n- Collect paperwork\n- Call the bank :call-bank\n- Private #hide reminder\n'

bob() {
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$scratch_root/config.yml" \
    BOB_DIR="$vault" \
    BOB_DAY_FILE="$vault/day.md" \
    BOB_NOW="2026-09-20 14:31:07" \
    TZ="UTC0" \
    "$bob_bin" "$@"
}

# Keep the offer-form parser contract in this real-Bob fixture flow as well as
# the capture response consumed by CaptureCore.
parse_draft='Finish the exit packet @cash:goog-exit@'
bob capture-parse --format json -- "$parse_draft" > "$scratch_root/parse.json"
python3 - "$scratch_root/parse.json" <<'PY'
import json
import pathlib
import sys

parsed = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert parsed.get("ok") is True, parsed
assert parsed.get("mode") == "pomodoro_project_note", parsed
marker = next(
    (span for span in parsed.get("spans", []) if span.get("kind") == "project_note_offer_marker"),
    None,
)
assert marker is not None and marker.get("project_note") == "offer", parsed
PY

fixture="$scratch_root/project-note-successors.json"
capture() {
  bob capture -b "$vault" --no-clip --format json "$@" -- "$draft"
}
if ! capture --dry-run > "$fixture" 2> "$scratch_root/dry-run.stderr"; then
  cat "$fixture" "$scratch_root/dry-run.stderr" >&2
  exit 1
fi
python3 - "$fixture" "$scratch_root" "$stable_root" \
  "$repo_root/Tests/Fixtures/project-note-successors.json" <<'PY'
import pathlib
import sys

source, scratch_root, stable_root, destination = map(pathlib.Path, sys.argv[1:])
text = source.read_text()
text = text.replace(str(scratch_root), str(stable_root))
pathlib.Path(destination).write_text(text)
PY

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
python3 - "$scratch_root/refusal.json" <<'PY'
import pathlib
import sys

message = pathlib.Path(sys.argv[1]).read_text().lower()
assert "pull-in" in message or "pull in" in message, message
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

echo "Generated project-note offer fixture and verified choice flow with $("$bob_bin" --version | head -n 1)"

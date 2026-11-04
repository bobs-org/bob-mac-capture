#!/usr/bin/env bash
# Record past-work `x=` payloads and spans from a built Bob.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-pomodoro-past-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-pomodoro-past-fixture"
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
    BOB_DAY_FILE="$1/2026/20261104.md" \
    BOB_NOW="2026-11-04 09:21:00" \
    TZ="UTC0" \
    "$bob_bin" "${@:2}"
}

bob_midnight() {
  env -i \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$scratch_root/config.yml" \
    BOB_DIR="$1" \
    BOB_DAY_FILE="$1/2026/20261104.md" \
    BOB_NOW="2026-11-04 23:58:00" \
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

vault_basic() {
  local vault="$1"
  mkdir -p "$vault/2026"
  cat > "$vault/bob.md" <<'EOF'
## Tasks
EOF
  printf '## Pomodoros\n- [ ] () \xe2\x80\x94 BUILD\n- [ ] () \xe2\x80\x94 FIX\n' > "$vault/2026/20261104.md"
}

vault_plan() {
  local vault="$1"
  local name="${2:-PLAN}"
  mkdir -p "$vault/2026"
  cat > "$vault/bob.md" <<'EOF'
## Tasks
EOF
  printf '## Pomodoros\n- [x] (**0855-0920** [t:: 25m]) \xe2\x80\x94 %s\n- [ ] () \xe2\x80\x94 BUILD\n- [ ] () \xe2\x80\x94 FIX\n' "$name" > "$vault/2026/20261104.md"
}

vault_links() {
  local vault="$1"
  mkdir -p "$vault/2026"
  cat > "$vault/bob.md" <<'EOF'
## Tasks

- [ ] #task First [created::2026-11-01] ^t1
- [ ] #task Second [created::2026-11-01] ^t2
EOF
  printf '## Pomodoros\n- [ ] () \xe2\x80\x94 BUILD\n\t- [[bob#^t1]]\n\t- [[bob#^t2]]\n' > "$vault/2026/20261104.md"
}

# Single past parse.
vault_basic "$scratch_root/vault-basic"
bob "$scratch_root/vault-basic" capture-parse --format json -- 'x=build' \
  > "$scratch_root/parse-single.json"

# Two-member stack parse.
bob "$scratch_root/vault-basic" capture-parse --format json -- 'x=build@2 x=fix@3' \
  > "$scratch_root/parse-stack.json"

# Repair spans parse.
bob "$scratch_root/vault-basic" capture-parse --format json -- 'x=build@2!' \
  > "$scratch_root/parse-repair.json"

# Multiple stacks separated by another item.
bob "$scratch_root/vault-basic" capture-parse --format json -- 'x=build@2' 'Buy milk' 'x=fix@3' \
  > "$scratch_root/parse-separated.json"

# Chain mixing an ordinary close with past recording.
bob "$scratch_root/vault-basic" capture-parse --format json -- 'x' 'x=build@2' \
  > "$scratch_root/parse-close-mix.json"

# Single preview.
bob "$scratch_root/vault-basic" capture --dry-run --format json -- 'x=build' \
  > "$scratch_root/preview-single.json"

# Two-member preview.
bob "$scratch_root/vault-basic" capture --dry-run --format json -- 'x=build@2 x=fix@3' \
  > "$scratch_root/preview-stack.json"

# Approved BUILD+FIX repair against PLAN.
vault_plan "$scratch_root/vault-plan" "PLAN"
bob "$scratch_root/vault-plan" capture --dry-run --format json -- 'x=build@2! x=fix@3!' \
  > "$scratch_root/preview-repair.json"

# Calendar trim against MEET.
vault_plan "$scratch_root/vault-meet" "MEET"
bob "$scratch_root/vault-meet" capture --dry-run --format json -- 'x=build@2! x=fix@3!' \
  > "$scratch_root/preview-calendar.json"

# Task effects and continuation.
vault_links "$scratch_root/vault-links"
bob "$scratch_root/vault-links" capture --dry-run --format json -- 'x==1!2' \
  > "$scratch_root/preview-task-effects.json"

# Work Log details.
bob "$scratch_root/vault-links" capture --dry-run --format json -- 'x==1 wired the lexer' \
  > "$scratch_root/preview-worklog.json"

# Refusal without repair (nonzero status expected).
set +e
bob "$scratch_root/vault-plan" capture --dry-run --format json -- 'x=build@2 x=fix@3' \
  > "$scratch_root/preview-refusal.json" 2> "$scratch_root/preview-refusal.stderr"
refusal_status=$?
set -e
if [[ $refusal_status -eq 0 ]]; then
  echo "expected refusal to fail" >&2
  exit 1
fi

# Completion for past names.
bob "$scratch_root/vault-basic" capture-complete --format json --cursor 4 -- 'x=bu' \
  > "$scratch_root/complete-name.json"

# Midnight ordering probe (best effort; failures keep the script green only
# when Bob refuses, which the test covers synthetically).
set +e
vault_basic "$scratch_root/vault-midnight"
bob_midnight "$scratch_root/vault-midnight" capture --dry-run --format json -- 'x=build@1 x=fix@1' \
  > "$scratch_root/preview-midnight.json" 2> /dev/null
midnight_status=$?
set -e
if [[ $midnight_status -ne 0 ]]; then
  rm -f "$scratch_root/preview-midnight.json"
fi

python3 - "$scratch_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def load(name):
    return json.loads((root / name).read_text())

# Parse contracts.
single = load("parse-single.json")
assert single["mode"] == "pomodoro_past", single
assert single["pomodoro_past"]["raw"] == "x=build", single
assert single["pomodoro_past"]["stack"]["index"] == 1, single

stack = load("parse-stack.json")
assert len(stack["items"]) == 2, stack
assert stack["items"][0]["pomodoro_past"]["stack"] == {
    "index": 1, "size": 2, "offset_blocks": 3,
}, stack
assert stack["items"][1]["pomodoro_past"]["stack"] == {
    "index": 2, "size": 2, "offset_blocks": 0,
}, stack

repair = load("parse-repair.json")
kinds = {span["kind"] for span in repair["spans"]}
assert "pomodoro_past" in kinds and "pomodoro_past_repair" in kinds, repair
assert repair["pomodoro_past"]["repair"] is True, repair

separated = load("parse-separated.json")
modes = [item["mode"] for item in separated.get("items", [])]
assert modes.count("pomodoro_past") == 2, separated

# Preview contracts.
preview_single = load("preview-single.json")
assert preview_single["kind"] == "pomodoro_past", preview_single
assert preview_single["placement"] == "recorded", preview_single
assert "pomodoro_close" not in preview_single, preview_single
assert preview_single["pomodoro_past"]["window"]["minutes"] == 25, preview_single

preview_stack = load("preview-stack.json")
captures = preview_stack.get("captures", [])
assert len(captures) == 2, preview_stack
assert captures[0]["pomodoro_past"]["stack"] == {"index": 1, "size": 2}, preview_stack

preview_repair = load("preview-repair.json")
repairs = preview_repair.get("captures", [preview_repair])
trims = [trim for item in repairs for trim in item.get("pomodoro_past", {}).get("trims", [])]
assert len(trims) == 1, preview_repair
assert trims[0]["before"] == "0855-0920" and trims[0]["after"] == "0855-0900", preview_repair
assert trims[0]["calendar"] is False, preview_repair
warnings = preview_repair.get("warnings", [])
assert any(w.get("code") == "pomodoro_past_trim" for w in warnings if isinstance(w, dict)), preview_repair

preview_calendar = load("preview-calendar.json")
cal_trims = [
    trim
    for item in preview_calendar.get("captures", [preview_calendar])
    for trim in item.get("pomodoro_past", {}).get("trims", [])
]
assert any(trim.get("calendar") is True for trim in cal_trims), preview_calendar

task_effects = load("preview-task-effects.json")
close = task_effects["pomodoro_past"]["close"]
assert len(close["tasks"]) == 2, task_effects
assert close["next_pomodoro"] is not None, task_effects

worklog = load("preview-worklog.json")
wclose = worklog["pomodoro_past"]["close"]
assert any(task.get("typed_work_log") for task in wclose["tasks"]), worklog

complete = load("complete-name.json")
assert complete["context"] == "pomodoro_past_name", complete
assert complete["replacement"] == {"start": 2, "end": 4}, complete

refusal = pathlib.Path(root / "preview-refusal.json").read_text()
assert "add !" in refusal, refusal
PY

persist "$scratch_root/parse-single.json" pomodoro-past-parse-single.json
persist "$scratch_root/parse-stack.json" pomodoro-past-parse-stack.json
persist "$scratch_root/parse-repair.json" pomodoro-past-parse-repair.json
persist "$scratch_root/parse-separated.json" pomodoro-past-parse-separated.json
persist "$scratch_root/parse-close-mix.json" pomodoro-past-parse-close-mix.json
persist "$scratch_root/preview-single.json" pomodoro-past-preview-single.json
persist "$scratch_root/preview-stack.json" pomodoro-past-preview-stack.json
persist "$scratch_root/preview-repair.json" pomodoro-past-preview-repair.json
persist "$scratch_root/preview-calendar.json" pomodoro-past-preview-calendar.json
persist "$scratch_root/preview-task-effects.json" pomodoro-past-preview-task-effects.json
persist "$scratch_root/preview-worklog.json" pomodoro-past-preview-worklog.json
persist "$scratch_root/preview-refusal.json" pomodoro-past-preview-refusal.json
persist "$scratch_root/complete-name.json" pomodoro-past-complete-name.json
if [[ -f "$scratch_root/preview-midnight.json" ]]; then
  persist "$scratch_root/preview-midnight.json" pomodoro-past-preview-midnight.json
fi
echo "wrote past pomodoro fixtures to $fixtures"

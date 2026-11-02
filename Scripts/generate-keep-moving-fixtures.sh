#!/usr/bin/env bash
# Generate keep-moving capture fixtures from a freshly built, real bob binary.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (for example bob-cli's target/release/bob)." >&2
  exit 1
fi

scratch_root="$(mktemp -d /tmp/bob-mac-capture-keep-moving-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-keep-moving-fixture"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
: > "$scratch_root/config.yml"

new_vault() {
  local vault="$1"
  mkdir -p "$vault"
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
      {"symbol":"-","name":"Canceled","type":"CANCELLED"}
    ]
  }
}
EOF
  cat > "$vault/dev.md" <<'EOF'
---
type: [[area]]
---
# Development
EOF
  cat > "$vault/sase.md" <<'EOF'
---
type: [[project]]
parent: [[dev]]
status: wip
---
- [ ] #task #prj Sase ^prj
EOF
  cat > "$vault/sase_badges.md" <<'EOF'
---
type: [[project]]
parent: [[sase]]
status: wip
---
- [ ] #task Draft the badge spec [id:: t] ^t
- [ ] #task #prj Badges ^prj
- [ ] #task Write badge docs [id:: a] ^a
- [*] #task Wire badges into the README [id:: b] ^b
- [/] #task Ship the badge renderer [id:: p] ^p
- [ ] #task Private reminder #hide [id:: h] ^h
EOF
}

bob() {
  local vault="$1"
  shift
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
    "$bob_bin" capture -b "$vault" --no-clip --format json --dry-run -- "$@"
}

persist() {
  python3 - "$1" "$scratch_root" "$stable_root" "$repo_root/Tests/Fixtures/$2" <<'PY'
import pathlib
import sys

source, scratch_root, stable_root, destination = sys.argv[1:]
contents = pathlib.Path(source).read_text().replace(scratch_root, stable_root)
pathlib.Path(destination).write_text(contents)
PY
}

task_vault="$scratch_root/task-vault"
new_vault "$task_vault"
cat > "$task_vault/20261005.md" <<'EOF'
## Pomodoros
- [ ] () — FIX
  - [[sase_badges#^t]]
EOF
bob "$task_vault" '!sase_badges:t' > "$scratch_root/task-complete.json"

close_vault="$scratch_root/close-vault"
new_vault "$close_vault"
cat > "$close_vault/20261005.md" <<'EOF'
## Pomodoros
- [ ] (**0920-0950**) — FIX
  - [[sase_badges#^t]]
EOF
bob "$close_vault" 'x!1' > "$scratch_root/pomodoro-close.json"

python3 - "$scratch_root/task-complete.json" "$scratch_root/pomodoro-close.json" <<'PY'
import json
import pathlib
import sys

task, close = (json.loads(pathlib.Path(path).read_text()) for path in sys.argv[1:])
assert task.get("ok") is True and task.get("dry_run") is True, task
assert task["task_complete"]["keep_moving"], task
assert close.get("ok") is True and close.get("dry_run") is True, close
assert close["pomodoro_close"]["keep_moving"], close
for row in task["task_complete"]["keep_moving"]:
    assert row["trigger"] == "last_planned", row
    assert row["offer"]["group"] == "keep_moving", row
PY

persist "$scratch_root/task-complete.json" task-complete-keep-moving.json
persist "$scratch_root/pomodoro-close.json" pomodoro-close-keep-moving.json
echo "Generated keep-moving fixtures with $("$bob_bin" --version | head -n 1)"

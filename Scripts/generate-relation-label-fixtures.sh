#!/usr/bin/env bash
# Generate truthful relation-label fixtures from this checkout's built Bob.
# Follows Scripts/generate-pomodoro-home-fixtures.sh conventions:
# isolated vault, BOB_BIN (not PATH bob), exact inputs documented below.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary (e.g. bob-cli's CARGO_TARGET_DIR/debug/bob)." >&2
  exit 1
fi
scratch_root="$(mktemp -d /tmp/bob-relation-label-fixture-vault.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
mkdir -p "$scratch_root/.obsidian/plugins/obsidian-tasks-plugin" "$scratch_root/done"
cat > "$scratch_root/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'JSON'
{
  "globalFilter": "#task",
  "statusSettings": {
    "coreStatuses": [
      {"symbol":" ","name":"Todo","type":"TODO"},
      {"symbol":"x","name":"Done","type":"DONE"}
    ],
    "customStatuses": [
      {"symbol":"*","name":"Next","type":"ON_HOLD"}
    ]
  }
}
JSON
cat > "$scratch_root/mac_inbox.md" <<'MD'
- [ ] #task Owner ^owner
  - 🪢 **LINKS:** [[tasks#^target|follow-up of]]
  - ⛓️ **DEPENDS ON:** [[tasks#^target]]
- [ ] #task Owner neighbor ^owner-neighbor
MD
cat > "$scratch_root/tasks.md" <<'MD'
- [ ] #task Target ^target
- [ ] #task Source ^source
  - 🪢 **LINKS:** follow-up of [[mac_inbox#^owner]]
- [ ] #task Malformed source ^malformed
  - 🪢 **LINKS:** see (old) [[mac_inbox#^owner]]
- [ ] #task Idless source
  - 🪢 **LINKS:** follow-up of [[mac_inbox#^owner]]
- [/] #task In progress ^progress
- [*] #task Next ^next
- [x] #task Closed ^closed
MD
cat > "$scratch_root/done/archive.md" <<'MD'
- [ ] #task Archived without ID
- [ ] #task Archived source ^archived-source
  - 🪢 **LINKS:** follow-up of [[mac_inbox#^owner]]
MD
complete() {
  local draft="$1"; local cursor="$2"; local out="$3"; shift 3
  BOB_DIR="$scratch_root" "$bob_bin" capture-complete --cursor "$cursor" --format json "$@" -- "$draft" > "$repo_root/Tests/Fixtures/$out"
}
parse() {
  local draft="$1"; local out="$2"
  "$bob_bin" capture-parse --format json -- "$draft" > "$repo_root/Tests/Fixtures/$out"
}
# Opening completions (narrow, empty query, no typed row).
complete 'New task ~tasks:target|' 23 relation-label-complete-to.json
complete 'New task ~~tasks:source|' 24 relation-label-complete-from.json
complete 'New task ~tasks:target| @work' 23 relation-label-complete-work.json
complete '~tasks:target| Fix it' 14 relation-label-complete-leading.json
complete 'Fix it ~tasks:target| &tasks:source' 21 relation-label-complete-dep.json
complete 'Fix ~"My Note":target|' 22 relation-label-complete-quoted.json
complete 'Hi 🧪 ~tasks:target|' 22 relation-label-complete-nonascii.json
complete 'Fix ~~tasks:source|' 19 relation-label-complete-trailing-from.json
complete '~~tasks:source| Fix it' 15 relation-label-complete-leading-from.json
# Synthetic empty probes (larger replacement, still no typed row).
complete 'New task ~tasks:target|" @work' 24 relation-label-complete-work-blank.json
complete 'Fix it ~tasks:target|" &tasks:source' 22 relation-label-complete-dep-blank.json
complete '~tasks:target|" Fix it' 15 relation-label-complete-leading-blank.json
complete 'Fix ~"My Note":target|"' 23 relation-label-complete-quoted-blank.json
complete 'Hi 🧪 ~tasks:target|"' 23 relation-label-complete-nonascii-blank.json
# Synthetic authored probes (larger replacement, Bob-authored typed row).
complete 'New task ~tasks:target|"follow @work' 30 relation-label-complete-work-follow.json
complete 'New task ~tasks:target|"see @work' 27 relation-label-complete-work-see.json
complete 'Fix it ~tasks:target|"see &tasks:source' 25 relation-label-complete-dep-see.json
complete '~tasks:target|"see Fix it' 18 relation-label-complete-leading-see.json
complete '~tasks:target|"follow Fix it' 21 relation-label-complete-leading-follow.json
complete 'Fix ~"My Note":target|"see' 26 relation-label-complete-quoted-see.json
complete 'Hi 🧪 ~tasks:target|"see' 26 relation-label-complete-nonascii-see.json
complete 'New task ~~tasks:source|"follow @work' 31 relation-label-complete-from-follow.json
# Parse fixtures for new opening drafts.
parse 'New task ~tasks:target|' relation-label-parse-to.json
parse 'New task ~~tasks:source|' relation-label-parse-from.json
parse 'New task ~tasks:target| @work' relation-label-parse-work.json
parse '~tasks:target| Fix it' relation-label-parse-leading.json
parse 'Fix it ~tasks:target| &tasks:source' relation-label-parse-dep.json
parse 'Fix ~"My Note":target|' relation-label-parse-quoted.json
parse 'Hi 🧪 ~tasks:target|' relation-label-parse-nonascii.json
parse 'Fix ~~tasks:source|' relation-label-parse-trailing-from.json
parse '~~tasks:source| Fix it' relation-label-parse-leading-from.json
echo "Generated relation-label fixtures with $($bob_bin --version | head -n 1)"

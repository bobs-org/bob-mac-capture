#!/usr/bin/env bash
# Generate truthful directive and clipboard fixtures from a real Bob.
#
#   BOB_BIN=/path/to/target/debug/bob BOB_CLI_DIR=/path/to/bob-cli \
#     Scripts/generate-directive-fixtures.sh
#
# BOB_BIN must be built from the bob-cli checkout named by BOB_CLI_DIR, and that
# checkout must contain the grammar-3 drawer work (commit e660c8d8) with a clean
# tree, because the binary carries no git revision of its own. The script verifies the
# binary reports `grammar` at or above the Mac gate
# (`CaptureGrammarGate.minimumRevision`), then persists, from one isolated vault, config, cache,
# state, HOME, and pinned clock:
#
#   directive-parse-*.json      bob capture-parse
#   directive-complete-*.json   bob capture-complete
#   directive-capture-*.json    bob capture --dry-run without clipboard reads
#   clip-*.json                 bob capture --dry-run clip previews and refusals
#   capture-template-*.json     bob capture --dry-run with `%t`
#   capture-templates-*.json    bob capture-templates save/list with `%t` or a refusal
#
# The clipboard is always mocked through BOB_CLIPBOARD_CMD and
# BOB_CLIPBOARD_HISTORY_CMD; the real pasteboard is never read. Every capture is a dry
# run, so Bob writes nothing, and the scratch directory is removed on exit. Only the
# scratch root inside Bob's output is rewritten to a stable path. The script also writes
# Tests/Fixtures/directive-fixtures-README.md, which records the Bob version, bob-cli
# revision, and every input.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
cli_dir="${BOB_CLI_DIR:-}"
prerequisite_commit="e660c8d8"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a bob binary built from BOB_CLI_DIR (for example its target/debug/bob)." >&2
  exit 1
fi
if [[ -z "$cli_dir" ]] || ! git -C "$cli_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Set BOB_CLI_DIR to the bob-cli checkout that BOB_BIN was built from." >&2
  exit 1
fi
if ! git -C "$cli_dir" merge-base --is-ancestor "$prerequisite_commit" HEAD; then
  echo "BOB_CLI_DIR does not contain the grammar-3 prerequisite $prerequisite_commit." >&2
  exit 1
fi
if [[ -n "$(git -C "$cli_dir" status --porcelain)" ]]; then
  echo "BOB_CLI_DIR has uncommitted changes; build and record a clean revision." >&2
  exit 1
fi
cli_revision="$(git -C "$cli_dir" rev-parse HEAD)"

scratch_root="$(mktemp -d /tmp/bob-mac-capture-directive-fixture-scratch.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-directive-fixture"
fixtures="$repo_root/Tests/Fixtures"
vault="$scratch_root/vault"
clip_dir="$scratch_root/clipboard"
day_file="$vault/2026/20261030.md"
empty_day_file="$scratch_root/empty-day.md"
config_default="$scratch_root/config.yml"
config_listen="$scratch_root/config-listen.yml"
mkdir -p "$vault/2026" "$clip_dir" "$scratch_root/"{home,config,state,cache}

# An empty config keeps every theme unconfigured and `highlights.listen_command` absent,
# so `%l` rows are disabled. The listen config enables them.
: > "$config_default"
cat > "$config_listen" <<'EOF'
highlights:
  listen_command: sase listen render
EOF
cat > "$vault/dev.md" <<'EOF'
---
type: "[[area]]"
---
# Dev

## Tasks
EOF
cat > "$vault/mac_inbox.md" <<'EOF'
---
type: "[[area]]"
---
# Mac inbox

## Tasks
EOF
cat > "$day_file" <<'EOF'
## Pomodoros
- [ ] (0900-0930) — FIX
EOF
printf '## Pomodoros\n' > "$empty_day_file"

# Mock clipboard: current content comes from one file, history from one JSON array
# (newest first) that the history command prints regardless of the requested count.
clip_file="$clip_dir/current.txt"
history_json="$clip_dir/history.json"
printf '' > "$clip_file"
printf '[]' > "$history_json"
cat > "$clip_dir/history.sh" <<'EOF'
#!/usr/bin/env bash
cat "$(dirname "$0")/history.json"
EOF
python3 - "$clip_dir" <<'PY'
import base64
import pathlib
import sys

clip_dir = pathlib.Path(sys.argv[1])
# A valid 1x1 PNG, so readable-thumbnail tests can point at a real image.
(clip_dir / "shot.png").write_bytes(
    base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM"
        "IQAAAABJRU5ErkJggg=="
    )
)
(clip_dir / "notes.pdf").write_bytes(b"%PDF-1.4\n%%EOF\n")
PY

bob_config="$config_default"
bob_day="$day_file"
clip_command="cat $clip_file"
history_command="bash $clip_dir/history.sh"
template_example_draft=$'Apply to {0}! @job_2026_apply_29:{1} %t\n- **URL**: {2}\n\nFoobar foo http://foobar.com/career/some_foo_job\nBazbuz baz https://example.com/baz\n"Two Sigma" two-sigma https://www.twosigma.com/careers/some_role'

# Every Bob call runs in a cleared environment so nothing from the real home, vault,
# config, display, or clipboard can leak into a fixture.
bob() {
  env -i \
    PATH="$PATH" \
    HOME="$scratch_root/home" \
    XDG_CONFIG_HOME="$scratch_root/config" \
    XDG_STATE_HOME="$scratch_root/state" \
    XDG_CACHE_HOME="$scratch_root/cache" \
    BOB_CONFIG_FILE="$bob_config" \
    BOB_DIR="$vault" \
    BOB_DAY_FILE="$bob_day" \
    BOB_NOW="2026-10-30 09:15:00" \
    BOB_CLIPBOARD_CMD="$clip_command" \
    BOB_CLIPBOARD_HISTORY_CMD="$history_command" \
    TZ="UTC0" \
    "$bob_bin" "$@"
}

gate_source="$repo_root/Sources/CaptureCore/CaptureGrammarGate.swift"
mac_gate="$(sed -n 's/.*minimumRevision *= *\([0-9][0-9]*\).*/\1/p' "$gate_source" | head -n 1)"
if ! printf '%s' "$mac_gate" | grep -Eq '^[0-9]+$'; then
  echo "Cannot parse CaptureGrammarGate.minimumRevision from $gate_source." >&2
  exit 1
fi

version_line="$("$bob_bin" --version | head -n 1)"
probe="$scratch_root/probe.json"
bob capture-parse --format json -- 'probe' > "$probe"
python3 - "$probe" "$mac_gate" <<'PY'
import json
import pathlib
import sys

probe_path, gate_arg = sys.argv[1], sys.argv[2]
gate = int(gate_arg)
grammar = json.loads(pathlib.Path(probe_path).read_text()).get("grammar")
if not isinstance(grammar, int) or grammar < gate:
    sys.exit(f"BOB_BIN reports grammar {grammar!r}; rebuild it from a bob-cli with grammar >= {gate}")
PY
probe_grammar="$(python3 - "$probe" <<'PY'
import json
import pathlib
import sys

print(json.loads(pathlib.Path(sys.argv[1]).read_text()).get("grammar"))
PY
)"

manifest="$scratch_root/manifest.md"
{
  echo "| Fixture | Command | Input | Setup |"
  echo "| --- | --- | --- | --- |"
} > "$manifest"

# Persist one raw Bob reply with only the unstable scratch root rewritten.
persist() {
  python3 - "$1" "$fixtures/$2" "$scratch_root" "$stable_root" <<'PY'
import json
import pathlib
import sys

source, destination, scratch_root, stable_root = sys.argv[1:]
text = pathlib.Path(source).read_text()
for prefix in ("/private" + scratch_root, scratch_root):
    text = text.replace(prefix, stable_root)
json.loads(text)
pathlib.Path(destination).write_text(text)
PY
}

describe() {
  local text="$1"
  text="${text//$'\n'/\\n}"
  text="${text//|/\\|}"
  text="${text//$scratch_root/$stable_root}"
  printf '%s' "$text"
}

# The non-default conditions in force for the next fixture; $1 is "clip" when the
# fixture reads the (mocked) clipboard.
setup() {
  local notes=()
  [[ "$bob_config" == "$config_listen" ]] && notes+=("\`highlights.listen_command\` configured")
  [[ "$bob_day" == "$empty_day_file" ]] && notes+=("no Pomodoro today")
  if [[ "${1:-}" == "clip" ]]; then
    notes+=("clipboard: $clip_desc")
    [[ -n "$history_desc" ]] && notes+=("history: $history_desc")
  fi
  local joined=""
  local note
  for note in "${notes[@]+"${notes[@]}"}"; do
    joined="${joined:+$joined; }$note"
  done
  printf '%s' "${joined:--}"
}

record() {
  printf '| `%s` | `%s` | `%s` | %s |\n' "$1" "$2" "$(describe "$3")" "$4" >> "$manifest"
}

parse() {
  local out="$1" draft="$2"
  bob capture-parse --format json -- "$draft" > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  record "$out" "capture-parse" "$draft" "$(setup)"
}

complete_at() {
  local out="$1" draft="$2" cursor="$3"
  bob capture-complete -b "$vault" --cursor "$cursor" --format json -- "$draft" \
    > "$scratch_root/raw.json"
  persist "$scratch_root/raw.json" "$out"
  record "$out" "capture-complete --cursor $cursor" "$draft" "$(setup)"
}

complete() {
  complete_at "$1" "$2" "$(printf '%s' "$2" | wc -c | tr -d ' ')"
}

# A capture dry run. $1 is the fixture, $2 the Bob exit status to accept (0 for a
# preview, 2 for a usage refusal, 1 for an I/O refusal), then Bob capture flags and the
# draft(s).
capture() {
  local out="$1" expected="$2"
  shift 2
  local status=0
  bob capture -b "$vault" --format json --dry-run "$@" > "$scratch_root/raw.json" || status=$?
  if [[ "$status" != "$expected" ]]; then
    echo "capture for $out exited $status (expected $expected):" >&2
    cat "$scratch_root/raw.json" >&2
    exit 1
  fi
  persist "$scratch_root/raw.json" "$out"
  local flags=()
  local args=()
  local reads_clip=clip
  while (($#)); do
    if [[ "$1" == "--" ]]; then
      shift
      args=("$@")
      break
    fi
    [[ "$1" == "--no-clip" ]] && reads_clip=""
    flags+=("$1")
    shift
  done
  record "$out" "capture --dry-run${flags[*]:+ ${flags[*]}}" "${args[*]}" "$(setup "$reads_clip")"
}

template_save() {
  local out="$1" expected="$2" draft="$3" origin="${4:-}"
  local status=0
  local args=(capture-templates save --format json)
  if [[ -n "$origin" ]]; then
    args+=(--template-origin "$origin")
  fi
  args+=(-- "$draft")
  bob "${args[@]}" > "$scratch_root/raw.json" || status=$?
  if [[ "$status" != "$expected" ]]; then
    echo "capture-templates save for $out exited $status (expected $expected):" >&2
    cat "$scratch_root/raw.json" >&2
    exit 1
  fi
  persist "$scratch_root/raw.json" "$out"
  record "$out" "capture-templates save --format json" "$draft" "$(setup)"
}

clip_desc=""
history_desc=""

# Mock the current clipboard ($1, described as $2 when given) and drop any history.
set_clip() {
  printf '%s' "$1" > "$clip_file"
  clip_desc="\`$(describe "${2:-${1//$clip_dir/CLIPBOARD_DIR}}")\`"
  history_desc=""
}

set_history() {
  printf '%s' "$1" > "$history_json"
  history_desc="\`$(describe "$1")\`"
}

# --- capture-parse: bare and typed markers, escapes, batches, Unicode, templates ---
parse directive-parse-bare-percent.json 'jot idea %'
parse directive-parse-bare-hash.json 'jot idea #'
parse directive-parse-ordinary-task.json 'Buy milk @grocery'
parse directive-parse-clip.json 'jot idea %c'
parse directive-parse-clip-one.json 'jot idea %c1'
parse directive-parse-clip-count.json 'jot idea %c3'
parse directive-parse-note.json 'jot idea %n'
parse directive-parse-listen-url.json 'https://example.com/post %l'
parse directive-parse-listen-route.json 'https://example.com/post %l @mac_inbox'
parse directive-parse-listen-mixed.json $'https://example.com/post %l\n\nhttps://example.org/other'
parse directive-parse-unknown.json 'jot idea %x'
parse directive-parse-escaped.json 'jot idea \%c'
parse directive-parse-literal-percent.json '100% done'
parse directive-parse-batch-later-item.json $'first\n\nsecond %c'
parse directive-parse-batch-three-items.json $'first %c\n\nsecond\n\nthird %c'
parse directive-parse-unicode.json 'naïve 🧰 %c3'
parse directive-parse-template.json $'Apply to {0} at {1} %t\n\nFoobar foo\nBaz bar'
parse directive-parse-template-example.json "$template_example_draft"
parse directive-parse-template-no-rows.json 'Apply {0} %t'
parse directive-parse-template-one-row.json $'Task {0} %t\n\nvalue'
parse directive-parse-template-arity-error.json $'Record {0} @work:{1} %t\n\nAcme abc extra'
parse directive-parse-template-clip.json $'Apply {0} %c %t\n\nx'
parse directive-parse-global-route.json $'@@dev\nFirst\n\nSecond'
parse directive-parse-global-route-bare.json '@@'
parse directive-parse-global-route-clip.json '@@dev jot idea %c'

# --- capture-complete: unselected menus, typed prefixes, disabled rows, offsets ---
complete directive-complete-bare.json 'jot idea %'
complete directive-complete-typed-clip.json 'jot idea %c'
complete directive-complete-typed-note.json 'jot idea %n'
complete directive-complete-typed-template.json 'jot idea %t'
complete directive-complete-counted-clip.json 'jot idea %c3'
complete directive-complete-later-item.json $'first\n\nsecond %'
complete directive-complete-unicode.json 'naïve 🧰 %'
complete directive-complete-template-clip.json 'Apply {0} %t %'
complete directive-complete-url-listen-disabled.json 'https://example.com/post %'
complete_at directive-complete-mid-draft.json 'jot % idea' 5
complete directive-complete-literal-percent.json '100%'
complete directive-complete-bare-hash.json 'jot idea #'
complete directive-complete-typed-hash.json 'jot idea #f'
complete directive-complete-global-route-bare.json '@@'
bob_config="$config_listen"
complete directive-complete-url-listen.json 'https://example.com/post %'
complete directive-complete-url-listen-typed.json 'https://example.com/post %l'
complete_at directive-complete-url-listen-route.json 'https://example.com/post %l' 24
parse directive-parse-listen-configured.json 'https://example.com/post %l'
bob_config="$config_default"
bob_day="$empty_day_file"
complete directive-complete-note-disabled.json 'jot idea %'
complete directive-complete-typed-note-disabled.json 'jot idea %n'
capture directive-capture-note-refused.json 1 --no-clip -- 'jot idea %n'
bob_day="$day_file"

# --- capture dry runs without clipboard reads: templates, global routes, refusals ---
capture directive-capture-template.json 0 --no-clip -- \
  $'Apply to {0} at {1} %t\n\nFoobar foo\nBaz bar'
capture directive-capture-global-route.json 0 --no-clip -- $'@@dev\nFirst\n\nSecond'
capture directive-capture-bare-percent-refused.json 2 --no-clip -- 'jot idea %'
capture directive-capture-bare-hash-refused.json 2 --no-clip -- 'jot idea #'
capture directive-capture-unknown-refused.json 2 --no-clip -- 'jot idea %x'
capture directive-capture-template-clip-refused.json 2 --no-clip -- \
  $'Apply {0} %c %t\n\nx'
capture capture-template-example.json 0 --no-clip -- \
  $'Apply to {0}! @job_2026_apply_29:{1} %t\n- **URL**: {2}\n\nFoobar foo http://foobar.com/career/some_foo_job\nBazbuz baz https://example.com/baz\n"Two Sigma" two-sigma https://www.twosigma.com/careers/some_role'
capture capture-template-one-row.json 0 --no-clip -- $'Task {0} %t\n\nvalue'
 bob_config="$config_listen"
capture ref-queued-listen.json 0 --no-clip -- 'https://example.com/post %l'
bob_config="$config_default"
saved_template_draft=$'Apply to {0}! @job_2026_apply_29:{1} %t\n- **URL**: {2}\n\n'
template_save capture-templates-save-new.json 0 "$saved_template_draft"
bob capture-templates --format json > "$scratch_root/raw.json"
persist "$scratch_root/raw.json" capture-templates-list-after-new.json
record capture-templates-list-after-new.json 'capture-templates --format json' \
  'one newly saved current-syntax template' "$(setup)"
template_save capture-templates-save-invalid.json 2 $'No fields %t\n\n'
template_save capture-templates-save-not-template.json 2 'Buy milk'
template_id="$(python3 - "$fixtures/capture-templates-save-new.json" <<'PY'
import json
import pathlib
import sys

print(json.loads(pathlib.Path(sys.argv[1]).read_text())["saved"]["id"])
PY
)"
template_save capture-templates-save-replaced.json 0 \
  $'Apply for {0} at {1} for {2} %t\n\n' "$template_id"
template_save capture-templates-save-reading.json 0 'Read {0} @reading^{1} $2 %t'
template_save capture-templates-save-grocery.json 0 'Buy {0} @grocery %t'
bob capture-templates --format json > "$scratch_root/raw.json"
persist "$scratch_root/raw.json" capture-templates-list-populated.json
record capture-templates-list-populated.json 'capture-templates --format json' \
  'three saved current-syntax templates' "$(setup)"
template_id="$(python3 - "$fixtures/capture-templates-list-populated.json" <<'PY'
import json
import pathlib
import sys

print(json.loads(pathlib.Path(sys.argv[1]).read_text())["templates"][0]["id"])
PY
)"
bob capture-templates delete 1 missing --format json > "$scratch_root/raw.json"
persist "$scratch_root/raw.json" capture-templates-delete.json
record capture-templates-delete.json 'capture-templates delete 1 missing --format json' \
  "index 1 ($template_id) plus a missing id" "$(setup)"
bob capture-templates --format json > "$scratch_root/raw.json"
persist "$scratch_root/raw.json" capture-templates-list-after-delete.json
record capture-templates-list-after-delete.json 'capture-templates --format json' \
  'current-syntax shelf after deleting index 1' "$(setup)"

# --- clip previews: every mode, history, and not_read ---
set_clip 'hello-clip'
capture clip-inline.json 0 -- 'jot idea %c'
set_clip $'- one\n- two'
capture clip-lines-list.json 0 -- 'jot idea %c'
set_clip $'line a\nline b'
capture clip-lines-plain.json 0 -- 'jot idea %c'
set_clip "$clip_dir/shot.png"
capture clip-attachments-image.json 0 -- 'jot idea %c'
set_clip "$clip_dir/shot.png"$'\n'"$clip_dir/notes.pdf"
capture clip-attachments-mixed.json 0 -- 'jot idea %c'
set_clip $'## Heading\nbody'
capture clip-snippet-heading.json 0 -- 'jot idea %c'
set_clip "$(python3 -c "print('long ' * 300)")" "'long ' repeated 300 times"
capture clip-snippet-long.json 0 -- 'jot idea %c'
set_clip 'first newest'
set_history '["first clipboard","first older clipboard","first oldest clipboard"]'
capture clip-history-one.json 0 -- 'jot idea %c3'
set_clip 'second newest'
set_history '["second clipboard","second older clipboard","second oldest clipboard"]'
capture clip-history-two.json 0 -- 'jot idea %c3'
set_clip 'newest'
set_history '["newest","older","oldest"]'
capture clip-history.json 0 -- 'jot idea %c3'
set_clip "$clip_dir/shot.png"
set_history '["older text"]'
capture clip-history-attachments.json 0 -- 'jot idea %c2'
set_clip 'hello-clip'
capture clip-not-read.json 0 --no-clip -- 'jot idea %c'
capture clip-not-read-count.json 0 --no-clip -- 'jot idea %c3'
set_clip 'hello-clip'
capture clip-batch.json 0 -- $'first %c\n\nsecond\n\nthird %c'
capture clip-batch-not-read.json 0 --no-clip -- $'first %c\n\nsecond %c3'
set_clip "$clip_dir/missing.png"
capture clip-error-missing-attachment.json 1 -- 'jot idea %c'
clip_command="false"
clip_desc="the command exits 1"
capture clip-error-unavailable.json 1 -- 'jot idea %c'
clip_command="cat $clip_file"
history_command="false"
set_clip 'newest'
history_desc="the command exits 1"
capture clip-error-history-unavailable.json 1 -- 'jot idea %c3'
history_command="bash $clip_dir/history.sh"

# --- verify the fixtures say what their names claim ---
python3 - "$fixtures" "$stable_root" "$mac_gate" <<'PY'
import json
import pathlib
import sys

fixtures = pathlib.Path(sys.argv[1])
stable_root = sys.argv[2]
mac_gate = int(sys.argv[3])


def load(name):
    return json.loads((fixtures / name).read_text())


def spans(name, kind="directive"):
    return [span for span in load(name)["spans"] if span["kind"] == kind]


def tokens(name):
    return [row["token"] for row in load(name)["candidates"]]


def disabled(name):
    return {
        row["token"]: row.get("disabled_reason")
        for row in load(name)["candidates"]
        if row.get("disabled_reason")
    }


for path in sorted(fixtures.glob("directive-*.json")) + sorted(fixtures.glob("clip-*.json")):
    reply = json.loads(path.read_text())
    if path.name.startswith(("directive-parse-", "directive-complete-")):
        assert reply["ok"] is True and reply["grammar"] >= mac_gate, path.name

# Parse.
assert load("directive-parse-bare-percent.json")["needs"] == ["directive"]
assert spans("directive-parse-bare-percent.json") == [{"start": 9, "end": 10, "kind": "directive"}]
assert load("directive-parse-bare-hash.json")["needs"] == ["task_type"]
assert spans("directive-parse-clip.json")[0]["directive"] == "clip"
assert "count" not in spans("directive-parse-clip.json")[0]
assert "count" not in spans("directive-parse-clip-one.json")[0]
assert spans("directive-parse-clip-count.json")[0]["count"] == 3
assert spans("directive-parse-note.json")[0]["directive"] == "note"
assert load("directive-parse-listen-url.json")["ref_listen"] is True
assert spans("directive-parse-listen-url.json")[0]["directive"] == "listen"
assert load("directive-parse-listen-route.json")["ref_listen"] is True
assert load("directive-parse-listen-mixed.json")["items"][0]["ref_listen"] is True
assert load("directive-parse-listen-mixed.json")["items"][1].get("ref_listen") is not True
assert any(d["code"] == "unknown_directive" for d in load("directive-parse-unknown.json")["diagnostics"])
assert spans("directive-parse-escaped.json") == []
assert spans("directive-parse-literal-percent.json") == []
assert spans("directive-parse-batch-later-item.json")[0]["directive"] == "clip"
assert len(load("directive-parse-batch-later-item.json")["items"]) == 2
unicode_span = spans("directive-parse-unicode.json")[0]
assert (unicode_span["start"], unicode_span["end"], unicode_span["count"]) == (12, 15, 3)
template = load("directive-parse-template.json")["template"]
assert "header" not in template and template["directive"]["line"] == 1
assert template["field_count"] == 2 and len(template["rows"]) == 2
assert spans("directive-parse-template.json")[0]["directive"] == "template"
assert load("directive-parse-template-no-rows.json")["needs"] == ["template_row"]
assert len(load("directive-parse-template-one-row.json")["template"]["rows"]) == 1
assert any(
    d["code"] == "template_row_arity"
    for d in load("directive-parse-template-arity-error.json")["diagnostics"]
)
assert any(
    d["code"] == "template_clipboard" for d in load("directive-parse-template-clip.json")["diagnostics"]
)
route = load("directive-parse-global-route.json")["global_destination"]
assert route["route"] == "dev" and "mode" not in route and "block_id" not in route
bare_route = load("directive-parse-global-route-bare.json")["global_destination"]
assert bare_route["route"] is None and bare_route["needs"] == ["route"]
assert "mode" not in bare_route and "block_id" not in bare_route
assert spans("directive-parse-global-route-clip.json")[-1]["directive"] == "clip"

# Completion.
bare = load("directive-complete-bare.json")
assert bare["context"] == "directive" and bare["initial_selection"] == "none"
assert tokens("directive-complete-bare.json") == ["%c", "%n", "%t"]
assert bare["candidates"][1]["detail"].startswith("→ 09:00")
for name in ("typed-clip", "typed-note", "typed-template", "counted-clip"):
    assert "initial_selection" not in load(f"directive-complete-{name}.json"), name
assert tokens("directive-complete-typed-clip.json") == ["%c"]
assert load("directive-complete-counted-clip.json")["candidates"] == []
assert "%t" in disabled("directive-complete-later-item.json")
unicode_complete = load("directive-complete-unicode.json")
assert (unicode_complete["replacement"]["start"], unicode_complete["replacement"]["end"]) == (12, 13)
assert "%c" in disabled("directive-complete-template-clip.json")
assert "%l" in disabled("directive-complete-url-listen-disabled.json")
assert load("directive-complete-mid-draft.json")["context"] is None
assert load("directive-complete-literal-percent.json")["context"] is None
assert load("directive-complete-bare-hash.json")["context"] == "task_type"
assert load("directive-complete-bare-hash.json")["initial_selection"] == "none"
assert "initial_selection" not in load("directive-complete-typed-hash.json")
assert tokens("directive-complete-url-listen.json") == ["%c", "%n", "%t", "%l"]
assert disabled("directive-complete-url-listen.json") == {}
assert tokens("directive-complete-url-listen-typed.json") == ["%l"]
assert load("directive-parse-listen-configured.json")["ref_listen"] is True
assert "%n" in disabled("directive-complete-note-disabled.json")
assert "%n" in disabled("directive-complete-typed-note-disabled.json")

# Refusals and previews.
for name in (
    "directive-capture-note-refused",
    "directive-capture-bare-percent-refused",
    "directive-capture-bare-hash-refused",
    "directive-capture-unknown-refused",
    "directive-capture-template-clip-refused",
    "clip-error-missing-attachment",
    "clip-error-unavailable",
    "clip-error-history-unavailable",
):
    assert load(f"{name}.json")["ok"] is False, name
assert load("directive-capture-bare-percent-refused.json")["code"] == "incomplete_directive"
assert load("directive-capture-bare-hash-refused.json")["code"] == "type_marker_needs_task"
assert load("directive-capture-unknown-refused.json")["code"] == "unknown_directive"
template_capture = load("directive-capture-template.json")
assert template_capture["ok"] is True and len(template_capture["captures"]) == 2
assert "header" not in template_capture["template"]
assert load("directive-parse-template-example.json")["template"]["field_count"] == 3
assert len(load("capture-template-example.json")["captures"]) == 3
assert load("capture-template-one-row.json")["template"]["row_count"] == 1
saved_template = load("capture-templates-save-new.json")["template"]
retired_template_header = "@@" + "template:"
assert "%t" in saved_template["draft"] and retired_template_header not in saved_template["draft"]
assert all(
    "%t" in template["draft"] and retired_template_header not in template["draft"]
    for template in load("capture-templates-list-populated.json")["templates"]
)
assert load("capture-templates-save-invalid.json")["ok"] is False
assert load("capture-templates-save-not-template.json")["ok"] is False
route_capture = load("directive-capture-global-route.json")
assert route_capture["ok"] is True and len(route_capture["captures"]) == 2

modes = {
    "clip-inline": "inline",
    "clip-lines-list": "lines",
    "clip-lines-plain": "lines",
    "clip-attachments-image": "attachments",
    "clip-attachments-mixed": "attachments",
    "clip-snippet-heading": "snippet",
    "clip-snippet-long": "snippet",
    "clip-history-one": "history",
    "clip-history-two": "history",
    "clip-history": "history",
    "clip-history-attachments": "history",
}
for name, mode in modes.items():
    clip = load(f"{name}.json")["clip"]
    assert clip["status"] == "read" and clip["mode"] == mode, name
    assert "header" not in clip, name
    assert all(key in clip for key in ("lines", "attachments", "entries")), name
    assert ("snippet" in clip) == (mode == "snippet"), name
assert [e["mode"] for e in load("clip-history.json")["clip"]["entries"]] == ["inline"] * 3
assert [e["lines"] for e in load("clip-history-one.json")["clip"]["entries"]] == [
    ["\t- first newest"], ["\t- first clipboard"], ["\t- first older clipboard"]
]
assert [e["lines"] for e in load("clip-history-two.json")["clip"]["entries"]] == [
    ["\t- second newest"], ["\t- second clipboard"], ["\t- second older clipboard"]
]
assert [e["mode"] for e in load("clip-history-attachments.json")["clip"]["entries"]] == [
    "attachments",
    "inline",
]
mixed = load("clip-attachments-mixed.json")["clip"]["attachments"]
assert [a["kind"] for a in mixed] == ["image", "file"], mixed
assert all(a["source"].startswith(stable_root) for a in mixed), mixed
assert load("clip-not-read.json")["clip"] == {"status": "not_read", "count": 1}
assert load("clip-not-read-count.json")["clip"] == {"status": "not_read", "count": 3}
batch = load("clip-batch.json")["captures"]
assert [c.get("clip", {}).get("status") for c in batch] == ["read", None, "read"], batch
batch_unread = load("clip-batch-not-read.json")["captures"]
assert [c["clip"] for c in batch_unread] == [
    {"status": "not_read", "count": 1},
    {"status": "not_read", "count": 3},
]
PY

# --- record the provenance and inputs ---
cat > "$fixtures/directive-fixtures-README.md" <<EOF
# Directive and clipboard wire fixtures

Regenerate the directive, template, and clipboard fixtures with:

\`\`\`bash
BOB_BIN=/path/to/bob-cli/target/debug/bob BOB_CLI_DIR=/path/to/bob-cli \\
  Scripts/generate-directive-fixtures.sh
\`\`\`

Generated with \`${version_line}\` built from bob-cli revision \`${cli_revision}\`
(grammar revision ${probe_grammar}, \`schema_version\` 1). The script refuses a binary that reports
below the Mac gate (\`CaptureGrammarGate.minimumRevision\` ${mac_gate}), a bob-cli checkout without
\`${prerequisite_commit}\`, or a dirty checkout.

Inputs are fully isolated: a scratch vault (\`dev.md\` and \`mac_inbox.md\` areas plus a
daily note with one running \`FIX\` Pomodoro at 09:00-09:30), an empty Bob config (and
a second config whose only setting is \`highlights.listen_command\`), a scratch HOME,
state, and cache, and the pinned clock \`BOB_NOW=2026-10-30 09:15:00\` with \`TZ=UTC0\`.
The clipboard is mocked through \`BOB_CLIPBOARD_CMD\` (a file the script rewrites per
case) and \`BOB_CLIPBOARD_HISTORY_CMD\` (a newest-first JSON array); the real pasteboard
is never read. Every capture is a dry run, so no file is written. Bob output is stored
unchanged except that the scratch root is rewritten to \`${stable_root}\`.

\`clip-attachments-*\` and \`clip-history-attachments\` point at \`${stable_root}/clipboard/shot.png\`
(a valid 1x1 PNG) and \`notes.pdf\`; those paths exist only while the script runs, so
tests substitute their own readable or missing source. \`CLIPBOARD_DIR\` in the table
below stands for \`${stable_root}/clipboard\`.

| Fixture | Command | Input | Setup |
| --- | --- | --- | --- |
EOF
tail -n +3 "$manifest" >> "$fixtures/directive-fixtures-README.md"

echo "Generated directive and clip fixtures with ${version_line} (bob-cli ${cli_revision})"

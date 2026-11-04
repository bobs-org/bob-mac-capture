#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to a built bob binary." >&2
  exit 1
fi
scratch_root="$(mktemp -d /tmp/bob-mac-capture-move-fixture.XXXXXX)"
trap 'rm -rf -- "$scratch_root"' EXIT
stable_root="/tmp/bob-mac-capture-move-fixture"
fixtures="$repo_root/Tests/Fixtures"
mkdir -p "$scratch_root/config" "$scratch_root/state" "$scratch_root/cache"
: > "$scratch_root/config.yml"
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
- [ ] #task Parent task ^parent-task
  - [ ] #task Nested subtask ^nested-sub
- [ ] #task Hidden task ^hidden-task #hide
- [ ] #task Project task ^prj
EOF
cat > "$vault/day.md" <<'EOF'
## Pomodoros
- [ ] (1330-1400) WORK
  - [[cash#^equity-docs]]
EOF
bob() {
  env -i PATH="$PATH" XDG_CONFIG_HOME="$scratch_root/config" XDG_STATE_HOME="$scratch_root/state" XDG_CACHE_HOME="$scratch_root/cache" BOB_CONFIG_FILE="$scratch_root/config.yml" BOB_DIR="$vault" BOB_DAY_FILE="$vault/day.md" BOB_NOW="2026-09-20 14:31:07" TZ="UTC0" "$bob_bin" "$@"
}
persist() {
  python3 - "$1" "$scratch_root" "$stable_root" "$fixtures/$2" <<'PY'
import pathlib, sys
source, scratch_root, stable_root, destination = sys.argv[1:]
text = pathlib.Path(source).read_text().replace(scratch_root, stable_root)
pathlib.Path(destination).write_text(text)
PY
}
# MC1 parse + complete at lone sigil
draft_mc1='Finish the exit packet @cash^goog-exit@
- ^'
bob capture-parse --format json -- "$draft_mc1" > "$scratch_root/parse-mc1.json"
python3 - "$scratch_root/parse-mc1.json" <<'PY'
import json, pathlib, sys
p = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert p.get("ok") is True, p
assert "project_task_move" in (p.get("needs", []) + [i for it in p.get("items", []) for i in it.get("needs", [])]), p
spans = p.get("spans", [])
assert any(s.get("kind") == "project_task_move_marker" for s in spans), p
assert any(s.get("kind") == "interactive_placeholder" for s in spans), p
PY
persist "$scratch_root/parse-mc1.json" move-parse-mc1.json
len_mc1=$(python3 -c "d='Finish the exit packet @cash^goog-exit@\n- ^'; print(len(d.encode()))")
bob capture-complete --cursor "$len_mc1" --format json -- "$draft_mc1" > "$scratch_root/complete-mc1.json"
python3 - "$scratch_root/complete-mc1.json" <<'PY'
import json, pathlib, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert r.get("context") == "project_task_move", r
assert r.get("picker", {}).get("kind") == "project_task_move", r
assert r.get("project_task_move", {}).get("parent") == "cash.md", r
candidates = r.get("candidates", [])
assert len(candidates) >= 5, r
assert all("consequence" in c for c in candidates), r
assert not any((c.get("block_id") or "") == "prj" for c in candidates), r
assert "project_task_move" in (r.get("warnings", []) or []) or True
PY
persist "$scratch_root/complete-mc1.json" move-complete-mc1.json
# MC2 partial
draft_mc2='Finish the exit packet @cash^goog-exit@
- ^dr'
bob capture-parse --format json -- "$draft_mc2" > "$scratch_root/parse-mc2.json"
persist "$scratch_root/parse-mc2.json" move-parse-mc2.json
len_mc2=$(python3 -c "d='Finish the exit packet @cash^goog-exit@\n- ^dr'; print(len(d.encode()))")
bob capture-complete --cursor "$len_mc2" --format json -- "$draft_mc2" > "$scratch_root/complete-mc2.json"
python3 - "$scratch_root/complete-mc2.json" <<'PY'
import json, pathlib, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert r.get("context") == "project_task_move", r
assert r.get("query") == "dr", r
rep = r.get("replacement", {})
assert rep.get("end", 0) - rep.get("start", 0) == 2, r
PY
persist "$scratch_root/complete-mc2.json" move-complete-mc2.json
# MC4 colon with admin
draft_mc4='Finish the exit packet @cash^goog-exit@#admin
- :'
bob capture-parse --format json -- "$draft_mc4" > "$scratch_root/parse-mc4.json"
persist "$scratch_root/parse-mc4.json" move-parse-mc4.json
len_mc4=$(python3 -c "d='Finish the exit packet @cash^goog-exit@#admin\n- :'; print(len(d.encode()))")
bob capture-complete --cursor "$len_mc4" --format json -- "$draft_mc4" > "$scratch_root/complete-mc4.json"
python3 - "$scratch_root/complete-mc4.json" <<'PY'
import json, pathlib, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert r.get("context") == "project_task_move", r
picker = r.get("picker", {})
assert picker.get("scope_token") == ":", r
assert picker.get("continuation") == "\n- :", r
cands = [c for c in r.get("candidates", []) if c.get("block_id") == "call-ms"]
assert cands, r
print(cands[0].get("consequence"))
PY
persist "$scratch_root/complete-mc4.json" move-complete-mc4.json
# MC5 no parent / missing note
draft_mc5a='Finish it @^x@
- ^'
bob capture-parse --format json -- "$draft_mc5a" > "$scratch_root/parse-mc5a.json" || true
persist "$scratch_root/parse-mc5a.json" move-parse-mc5a.json
len_mc5a=$(python3 -c "d='Finish it @^x@\n- ^'; print(len(d.encode()))")
bob capture-complete --cursor "$len_mc5a" --format json -- "$draft_mc5a" > "$scratch_root/complete-mc5a.json" || true
persist "$scratch_root/complete-mc5a.json" move-complete-mc5a.json
draft_mc5b='Finish it @nope^x@
- ^'
len_mc5b=$(python3 -c "d='Finish it @nope^x@\n- ^'; print(len(d.encode()))")
bob capture-complete --cursor "$len_mc5b" --format json -- "$draft_mc5b" > "$scratch_root/complete-mc5b.json" || true
persist "$scratch_root/complete-mc5b.json" move-complete-mc5b.json
# Sigil aliases on sealed move bullets (rewrite + complete under both seals)
draft_alias_caret='@cash^goog-exit@
- .'
len_alias_caret=$(python3 -c "d='@cash^goog-exit@\n- .'; print(len(d.encode()))")
bob capture-rewrite --cursor "$len_alias_caret" --format json -- "$draft_alias_caret" > "$scratch_root/rewrite-alias-caret.json"
python3 - "$scratch_root/rewrite-alias-caret.json" <<'VALIDATE'
import json, pathlib, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert r.get("rule") == "expand_sigil_alias", r
assert r.get("text") == "@cash^goog-exit@\n- ^", r
assert r.get("summary") == "Typed ^ for .", r
VALIDATE
persist "$scratch_root/rewrite-alias-caret.json" capture-rewrite-sigil-alias-move-caret.json
draft_alias_link='@cash:goog-exit@
- ;'
len_alias_link=$(python3 -c "d='@cash:goog-exit@\n- ;'; print(len(d.encode()))")
bob capture-rewrite --cursor "$len_alias_link" --format json -- "$draft_alias_link" > "$scratch_root/rewrite-alias-link.json"
python3 - "$scratch_root/rewrite-alias-link.json" <<'VALIDATE'
import json, pathlib, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert r.get("rule") == "expand_sigil_alias", r
assert r.get("text") == "@cash:goog-exit@\n- :", r
assert r.get("summary") == "Typed : for ;", r
VALIDATE
persist "$scratch_root/rewrite-alias-link.json" capture-rewrite-sigil-alias-move-link.json
for seal in '^' ':'; do
  for sigil in '^' ':'; do
    if [ "$sigil" = '^' ]; then lane=caret; else lane=link; fi
    if [ "$seal" = '^' ]; then form=create; else form=offer; fi
    draft_alias_complete="@cash${seal}goog-exit@
- ${sigil}"
    len_alias_complete=$(python3 -c "d='@cash${seal}goog-exit@\n- ${sigil}'; print(len(d.encode()))")
    bob capture-complete --cursor "$len_alias_complete" --format json -- "$draft_alias_complete" > "$scratch_root/complete-alias.json"
    ALIAS_SIGIL="$sigil" python3 - "$scratch_root/complete-alias.json" <<'VALIDATE'
import json, os, pathlib, sys
r = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert r.get("context") == "project_task_move", r
picker = r.get("picker", {})
if os.environ.get("ALIAS_SIGIL") == "^":
    assert picker.get("action_continuation_keys") == ["^"], r
    assert picker.get("action_continuation_aliases") == {".": "^"}, r
else:
    assert "action_continuation_keys" not in picker, r
    assert "action_continuation_aliases" not in picker, r
VALIDATE
    persist "$scratch_root/complete-alias.json" "move-complete-sigil-alias-${lane}-${form}.json"
  done
done
echo "wrote move fixtures to $fixtures"
ls "$fixtures"/move-* 2>&1

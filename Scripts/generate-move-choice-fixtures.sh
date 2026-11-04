#!/usr/bin/env bash
# Real-bob MQ5/MQ11/MQ12/MQ16 previews and MQ7/MQ10 answered captures.
set -euo pipefail
: "${BOB_BIN:?Set BOB_BIN to bob built from current bob-cli master}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$BOB_BIN" "$repo_root/Tests/Fixtures" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary, destination = sys.argv[1:]
parent = '''---
type: "[[area]]"
---
# Cash
## Tasks
- [ ] #task Collect the equity paperwork ^equity-docs
- [ ] #task Renew the passport
- [ ] #task Pay the credit card ^pay-cc
## Admin
- [ ] #task Hidden expense report #hide ^expenses
- [x] #task Done task ^done
'''
base = 'Finish the exit packet @cash^goog-exit@\n- Draft the memo ^memo\n- ^pay-cc\n- ^^\n- Book the lawyer ^lawyer'
offer = base.replace('@cash^', '@cash:')
with tempfile.TemporaryDirectory(prefix='bob-mac-capture-move-choice-') as temp:
    root = Path(temp)
    (root / 'config.yml').write_text('')
    for name, draft, args in [
        ('mq5', base, ['--dry-run']),
        ('mq11', base, ['--dry-run']),
        ('mq12', base.replace('@\n', '@ s:3\n', 1), ['--dry-run']),
        ('mq16', base.replace('@\n', '@#admin\n', 1), ['--dry-run']),
        ('offer', offer, ['--dry-run']),
        ('mq7', base.replace('@\n', '@#admin\n', 1), ['--move-in', '1,:2']),
        ('mq10', offer, ['--move-in', '1,:2', '--pull-in', 'none']),
    ]:
        vault = root / name
        vault.mkdir()
        (vault / 'cash.md').write_text(parent.replace('[ ] #task Pay', '[?] #task Pay') if name == 'mq12' else parent)
        (vault / 'day.md').write_text('## Pomodoros\n- [ ] (1330-1400) WORK\n## Daily\n')
        env = dict(PATH=os.environ['PATH'], BOB_DIR=str(vault), BOB_DAY_FILE=str(vault/'day.md'),
                   BOB_NOW='2026-11-04 14:31:07', TZ='UTC0', BOB_CONFIG_FILE=str(root/'config.yml'),
                   XDG_CONFIG_HOME=str(root/'config'), XDG_STATE_HOME=str(root/'state'),
                   XDG_CACHE_HOME=str(root/'cache'))
        result = subprocess.run([binary, 'capture', '--format', 'json', *args, '--', draft],
                                env=env, text=True, capture_output=True)
        assert result.returncode == 0, (name, result.stdout, result.stderr)
        payload = json.loads(result.stdout)
        assert payload['ok'] and payload['move_choice']['supported'], result.stdout
        slot = payload['move_choice']['slots'][0]
        start, end = slot['draft_range']
        assert draft.encode()[start:end] == b'^^'
        if name in ('mq7', 'mq10'):
            assert slot['answered'] and slot['moved_count'] == 2 and slot['linked_count'] == 1
            assert (vault/'cash_goog_exit.md').exists()
        text = result.stdout.replace(temp, '/tmp/bob-mac-capture-move-choice-fixture')
        (Path(destination)/f'move-choice-{name}.json').write_text(text)
PY

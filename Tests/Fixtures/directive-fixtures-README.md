# Directive and clipboard wire fixtures

Regenerate every `directive-*.json` and `clip-*.json` file with:

```bash
BOB_BIN=/path/to/bob-cli/target/debug/bob BOB_CLI_DIR=/path/to/bob-cli \
  Scripts/generate-directive-fixtures.sh
```

Generated with `bob 0.4.0` built from bob-cli revision `a1dcb64eee30a3e7f45b0555be8cf60b940d85e1`
(grammar revision 2, `schema_version` 1). The script refuses a binary that reports a
lower grammar, a bob-cli checkout without `b290d833`, or a dirty checkout.

Inputs are fully isolated: a scratch vault (`dev.md` and `mac_inbox.md` areas plus a
daily note with one running `FIX` Pomodoro at 09:00-09:30), an empty Bob config (and
a second config whose only setting is `highlights.listen_command`), a scratch HOME,
state, and cache, and the pinned clock `BOB_NOW=2026-10-30 09:15:00` with `TZ=UTC0`.
The clipboard is mocked through `BOB_CLIPBOARD_CMD` (a file the script rewrites per
case) and `BOB_CLIPBOARD_HISTORY_CMD` (a newest-first JSON array); the real pasteboard
is never read. Every capture is a dry run, so no file is written. Bob output is stored
unchanged except that the scratch root is rewritten to `/tmp/bob-mac-capture-directive-fixture`.

`clip-attachments-*` and `clip-history-attachments` point at `/tmp/bob-mac-capture-directive-fixture/clipboard/shot.png`
(a valid 1x1 PNG) and `notes.pdf`; those paths exist only while the script runs, so
tests substitute their own readable or missing source. `CLIPBOARD_DIR` in the table
below stands for `/tmp/bob-mac-capture-directive-fixture/clipboard`.

| Fixture | Command | Input | Setup |
| --- | --- | --- | --- |
| `directive-parse-bare-percent.json` | `capture-parse` | `jot idea %` | - |
| `directive-parse-bare-hash.json` | `capture-parse` | `jot idea #` | - |
| `directive-parse-clip.json` | `capture-parse` | `jot idea %c` | - |
| `directive-parse-clip-one.json` | `capture-parse` | `jot idea %c1` | - |
| `directive-parse-clip-count.json` | `capture-parse` | `jot idea %c3` | - |
| `directive-parse-note.json` | `capture-parse` | `jot idea %n` | - |
| `directive-parse-listen-url.json` | `capture-parse` | `https://example.com/post %l` | - |
| `directive-parse-unknown.json` | `capture-parse` | `jot idea %x` | - |
| `directive-parse-escaped.json` | `capture-parse` | `jot idea \%c` | - |
| `directive-parse-literal-percent.json` | `capture-parse` | `100% done` | - |
| `directive-parse-batch-later-item.json` | `capture-parse` | `first\n\nsecond %c` | - |
| `directive-parse-unicode.json` | `capture-parse` | `naïve 🧰 %c3` | - |
| `directive-parse-template.json` | `capture-parse` | `Apply to {0} at {1} %t\n\nFoobar foo\nBaz bar` | - |
| `directive-parse-template-no-rows.json` | `capture-parse` | `Apply {0} %t` | - |
| `directive-parse-template-clip.json` | `capture-parse` | `Apply {0} %c %t\n\nx` | - |
| `directive-parse-global-route.json` | `capture-parse` | `@@dev\nFirst\n\nSecond` | - |
| `directive-parse-global-route-bare.json` | `capture-parse` | `@@` | - |
| `directive-parse-global-route-clip.json` | `capture-parse` | `@@dev jot idea %c` | - |
| `directive-complete-bare.json` | `capture-complete --cursor 10` | `jot idea %` | - |
| `directive-complete-typed-clip.json` | `capture-complete --cursor 11` | `jot idea %c` | - |
| `directive-complete-typed-note.json` | `capture-complete --cursor 11` | `jot idea %n` | - |
| `directive-complete-typed-template.json` | `capture-complete --cursor 11` | `jot idea %t` | - |
| `directive-complete-counted-clip.json` | `capture-complete --cursor 12` | `jot idea %c3` | - |
| `directive-complete-later-item.json` | `capture-complete --cursor 15` | `first\n\nsecond %` | - |
| `directive-complete-unicode.json` | `capture-complete --cursor 13` | `naïve 🧰 %` | - |
| `directive-complete-template-clip.json` | `capture-complete --cursor 14` | `Apply {0} %t %` | - |
| `directive-complete-url-listen-disabled.json` | `capture-complete --cursor 26` | `https://example.com/post %` | - |
| `directive-complete-mid-draft.json` | `capture-complete --cursor 5` | `jot % idea` | - |
| `directive-complete-literal-percent.json` | `capture-complete --cursor 4` | `100%` | - |
| `directive-complete-bare-hash.json` | `capture-complete --cursor 10` | `jot idea #` | - |
| `directive-complete-typed-hash.json` | `capture-complete --cursor 11` | `jot idea #f` | - |
| `directive-complete-url-listen.json` | `capture-complete --cursor 26` | `https://example.com/post %` | `highlights.listen_command` configured |
| `directive-complete-url-listen-typed.json` | `capture-complete --cursor 27` | `https://example.com/post %l` | `highlights.listen_command` configured |
| `directive-parse-listen-configured.json` | `capture-parse` | `https://example.com/post %l` | `highlights.listen_command` configured |
| `directive-complete-note-disabled.json` | `capture-complete --cursor 10` | `jot idea %` | no Pomodoro today |
| `directive-complete-typed-note-disabled.json` | `capture-complete --cursor 11` | `jot idea %n` | no Pomodoro today |
| `directive-capture-note-refused.json` | `capture --dry-run --no-clip` | `jot idea %n` | no Pomodoro today |
| `directive-capture-template.json` | `capture --dry-run --no-clip` | `Apply to {0} at {1} %t\n\nFoobar foo\nBaz bar` | - |
| `directive-capture-global-route.json` | `capture --dry-run --no-clip` | `@@dev\nFirst\n\nSecond` | - |
| `directive-capture-bare-percent-refused.json` | `capture --dry-run --no-clip` | `jot idea %` | - |
| `directive-capture-bare-hash-refused.json` | `capture --dry-run --no-clip` | `jot idea #` | - |
| `directive-capture-unknown-refused.json` | `capture --dry-run --no-clip` | `jot idea %x` | - |
| `directive-capture-template-clip-refused.json` | `capture --dry-run --no-clip` | `Apply {0} %c %t\n\nx` | - |
| `clip-inline.json` | `capture --dry-run` | `jot idea %c` | clipboard: `hello-clip` |
| `clip-lines-list.json` | `capture --dry-run` | `jot idea %c` | clipboard: `- one\n- two` |
| `clip-lines-plain.json` | `capture --dry-run` | `jot idea %c` | clipboard: `line a\nline b` |
| `clip-attachments-image.json` | `capture --dry-run` | `jot idea %c` | clipboard: `CLIPBOARD_DIR/shot.png` |
| `clip-attachments-mixed.json` | `capture --dry-run` | `jot idea %c` | clipboard: `CLIPBOARD_DIR/shot.png\nCLIPBOARD_DIR/notes.pdf` |
| `clip-snippet-heading.json` | `capture --dry-run` | `jot idea %c` | clipboard: `## Heading\nbody` |
| `clip-snippet-long.json` | `capture --dry-run` | `jot idea %c` | clipboard: `'long ' repeated 300 times` |
| `clip-history.json` | `capture --dry-run` | `jot idea %c3` | clipboard: `newest`; history: `["newest","older","oldest"]` |
| `clip-history-attachments.json` | `capture --dry-run` | `jot idea %c2` | clipboard: `CLIPBOARD_DIR/shot.png`; history: `["older text"]` |
| `clip-not-read.json` | `capture --dry-run --no-clip` | `jot idea %c` | - |
| `clip-not-read-count.json` | `capture --dry-run --no-clip` | `jot idea %c3` | - |
| `clip-batch.json` | `capture --dry-run` | `first %c\n\nsecond\n\nthird %c` | clipboard: `hello-clip` |
| `clip-batch-not-read.json` | `capture --dry-run --no-clip` | `first %c\n\nsecond %c3` | - |
| `clip-error-missing-attachment.json` | `capture --dry-run` | `jot idea %c` | clipboard: `CLIPBOARD_DIR/missing.png` |
| `clip-error-unavailable.json` | `capture --dry-run` | `jot idea %c` | clipboard: the command exits 1 |
| `clip-error-history-unavailable.json` | `capture --dry-run` | `jot idea %c3` | clipboard: `newest`; history: the command exits 1 |

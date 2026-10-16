# Ref today contract fixtures

The original seven envelopes are the real `bob ref today -f json` outputs attached to
bob-cli-8f.1, notes 1–2 (2026-10-16), from a scratch vault with
`BOB_NOW=2026-10-16 09:15:00`. The three refusal/reload envelopes below were generated
on 2026-10-16 by the repaired CLI against separate scratch vaults with the same fixed
clock. No fixture was produced from the real vault. In all ten files, only absolute
scratch-vault prefixes were replaced with `/tmp/bob`; values, fields, and selectors are
otherwise unchanged.

- `listing`: automatic dry run, Ready → Next under CURRENT.
- `linked`: the committed automatic link.
- `created`: create FOCUS.
- `moved`: move an existing link from CURRENT into newly created FOCUS.
- `already-current`: keep a Next task under READING, with no file changes.
- `link-guard`: consume a project-blocked gesture without linking.
- `multiple-running`: exit 1 with rows and no implicit default. Bob deliberately
  marks neither timed entry as `running` in this ambiguous case.
- `no-reading-task`: refuse a reference without a reading task.
- `stale-pomodoro`: refuse a stale entry ref so the client reloads current rows.
- `reading-task-closed`: refuse an already-read reference.

`fake-bob` uses `refs-today-listing.json` for `-d` and `refs-today-linked.json`
for writes. `FAKE_BOB_REF_TODAY_FIXTURE` overrides the response;
`FAKE_BOB_REF_TODAY_EXIT` controls its exit status (2 emits no JSON to model an
older bob). The existing `FAKE_BOB_RECORD_PATH` records argv.

# Pomodoro homes wire fixtures

Regenerate the homes-bearing Ref Today, unnamed restart, and completion payloads with
the current installed Bob CLI:

```bash
Scripts/generate-pomodoro-home-fixtures.sh
```

The script pins `BOB_NOW=2026-10-16 09:15:00` and `plan.exempt: [GTD]`, builds an
isolated scratch vault at `/tmp/bob-pomodoro-homes-fixture-vault`, and removes it when
complete. It calls
real `bob ref today -d -f json`, `bob capture --dry-run -f json`, and both
`bob capture-complete` forms (`=#` and `=3#`). `BOB_BIN` can select a particular
installed Bob executable. The fixtures retain the CLI's JSON bytes, including the
deterministic scratch target path. The existing named completion fixtures remain as
no-homes compatibility payloads.

`refs-today-homes.json` is a dry-run output from a reference note linked to an unnamed
running Pomodoro and a named future Pomodoro. The named row correctly omits `homes`;
the unnamed row carries its real forecast parts.

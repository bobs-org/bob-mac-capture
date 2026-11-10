# Private event note fixtures

These full schema-1 JSON responses are copied from bob-cli's
`tests/fixtures/gcal_note/json/`. Their source is the synthetic FakeGog
integration coverage in `tests/gcal_note_cli.rs`; they contain no live Google
or personal event data. The source tests normalize only the rolling list-window
timestamps/dates and retain realistic event times, day-based paths, and valid
synthetic Calendar URLs.

Regenerate in bob-cli with:

```sh
BOB_UPDATE_GCAL_NOTE_FIXTURES=1 cargo test --test gcal_note_cli
```

Then copy the JSON files from `tests/fixtures/gcal_note/json/` into this
directory. Mac tests read only these local copies and do not require a sibling
checkout. `Tests/Fixtures/fake-bob` selects per-operation files through
`FAKE_BOB_GCAL_NOTE_{LIST,SHOW,PREVIEW,WRITE,CLEAR}_FIXTURE`, records exact argv,
and can simulate delays, explicit errors, and a temporary note store.

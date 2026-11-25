# Meeting Notes JSON fixtures

These compact schema-1 fixtures use fictional meetings and destinations. They
are authored against the public `bob ref meet` wire structs and checked against
the synthetic CLI coverage in bob-cli's `tests/cli/highlights/meet_cli.rs`.
They contain no clipboard, vault, calendar, or personal data.

When the CLI contract changes, run the focused synthetic suite in bob-cli:

```sh
cargo test --test cli highlights::meet_cli
```

Use the emitted JSON from a temporary synthetic vault to update these minimized
examples, keeping one fixture for each result shape. `fake-bob` selects them
through `FAKE_BOB_MEETING_NOTES_FIXTURE_MAP` or the operation-specific fixture
environment variables and records exact argv in a temporary file.

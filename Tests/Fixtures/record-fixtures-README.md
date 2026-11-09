# Record fixtures

Generated from a real Bob; never hand-edit the JSON.

- bob: 941ee724
- config: restaurant (eat, 🍽️) + podcast (podcasts), companions default [[kelly]]
- vault: eat/nagi.md, eat/ramen_ya.md, eat/cafe_moo.md, eat/pizza_roma.md,
  eat/taco_luna.md, eat/thai_orchid.md, eat/burger_joint.md, eat/sushi_den.md,
  podcasts/techmeme.md
- clock: 2026-10-30 09:00:00, TZ=UTC0, isolated XDG dirs, scratch vault only
- command shapes: capture-parse (including field/value caret drafts),
  capture-complete (caret, -n, -F, route, section, create-route
  record_target, 7+ category values, current-value named edit),
  capture-targets

Capture fixtures (`record-capture-*.json`) were generated separately with
the same config, vault, and clock by
`Scripts/generate-record-fixtures.sh` from a Bob carrying the per-item
`record_note` wire change (bob-cli base 97f0b8f1 plus that uncommitted
change; bead bob-cli-ir.11):

- `record-capture-restaurant.json`: dry-run restaurant with choice
  glyphs, an aliased `[[kelly|Kel]]` companion, Unicode/quotes/colons in
  the title, a date, and nested notes.
- `record-capture-restaurant-commit.json`: commit of the same draft;
  `record_note` and `note_files[].markdown` match the dry run.
- `record-capture-podcast.json`: dry-run podcast with no authored notes.
- `record-capture-two-records.json`: dry-run with two record items.
- `record-capture-mixed.json`: dry-run with a task item plus a record
  item; the task item omits `record_note`.
- `record-capture-missing.json`, `record-capture-invalid.json`:
  dry-run refusals (exit 2) with `draft`, `missing[]`, and `invalid[]`.
- `record-capture-optional-empty.json`: dry-run with an explicit empty
  optional property (key and label only, no value or display).

Older-Bob fixtures (no record keys) are checked in by hand:
record-parse-old-bob.json, record-complete-old-bob.json,
record-targets-old-bob.json.

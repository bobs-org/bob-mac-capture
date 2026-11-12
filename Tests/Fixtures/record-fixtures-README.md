# Record fixtures

Generated from a real Bob; never hand-edit the JSON.

- bob: 6e421597
- albums: eat (restaurant, 🍽️, owner body) + podcasts (podcast, 🎙️, owner dev),
  companions default [[kelly]]; the config carries no records: block
- vault: eat.md + podcasts.md album notes, eat/nagi.md, eat/ramen_ya.md, eat/cafe_moo.md,
  eat/pizza_roma.md, eat/taco_luna.md, eat/thai_orchid.md, eat/burger_joint.md,
  eat/sushi_den.md, podcasts/techmeme.md
- clock: 2026-10-30 09:00:00, TZ=UTC0, isolated XDG dirs, scratch vault only
- command shapes: capture-parse (including field/value caret drafts,
  existing-record @eat/nagi, title-first update with status:: liked,
  bare-album Blaze @eat refusal),
  capture-complete (caret, -n, -F, route, section, create-route
  record_target, 7+ category values, current-value named edit),
  capture --dry-run (restaurant with choice glyphs, aliased link,
  Unicode/quotes/colons, nested notes; podcast with no notes; two
  records; mixed task/record; missing, invalid, and bare-album refusals; explicit
  empty optional; existing-record note append), one capture commit,
  capture-targets

Older-Bob fixtures (no record keys) are checked in by hand:
record-parse-old-bob.json, record-complete-old-bob.json,
record-targets-old-bob.json.

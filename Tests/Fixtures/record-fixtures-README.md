# Record fixtures

Generated from a real Bob; never hand-edit the JSON.

- bob: bob 0.5.0
- albums: eat (restaurant, 🍽️, owner body) + podcasts (podcast, 🎙️, owner dev) + movies (movie, 🎬, owner body),
  companions default [[kelly]]; the config carries no records: block
- vault: eat.md + podcasts.md + movies.md album notes, eat/nagi.md, eat/ramen_ya.md, eat/cafe_moo.md,
  eat/pizza_roma.md, eat/taco_luna.md, eat/thai_orchid.md, eat/burger_joint.md,
  eat/sushi_den.md, podcasts/techmeme.md; dev.md has ID-bearing Plan dinner
  and ID-less Book a table tasks
- clock: 2026-10-30 09:00:00, TZ=UTC0, isolated XDG dirs, scratch vault only
- command shapes: capture-parse (including field/value caret drafts,
  optional visited:: caret with all required fields set, also completed
  at the draft's end without -n or -F,
  existing-record @eat/nagi, title-first update with status:: liked,
  bare-album Blaze @eat refusal, title-less @eat/ record route, title-bearing
  movie incomplete "The Little Mermaid @movies/ " plus buy-milk/empty
  variants, Blaze @eat/ incomplete, and the "The Little Mermaid @mo"
  partial-route parse, plus create/update editor-assist drafts),
  capture-complete (caret, -n, -F, route, section, create-route
  record_target including title-less @eat/, 7+ category values,
  current-value named edit, movie next-missing (mermaid, buy-milk, empty)
  and Blaze next-missing); create/update note bullets with [[d, [[de,
  accepted [[dev]], and (( (with --all-tasks for Task Wikilink rows),
  capture-rewrite (title-less @eat/ stays
  literal),
  capture --dry-run (restaurant with choice glyphs, aliased link,
  Unicode/quotes/colons, nested notes; podcast with no notes; two
  records; mixed task/record; missing, invalid, bare-album, and Blaze
  incomplete refusals; explicit empty optional; existing-record note
  append), one capture commit, capture-targets

Regeneration also refreshes older fixtures to the current Bob output:
grammar 28, album-index previews, omitted empty Notes headings, the movies
route/target, and current category suggestion ordering. The scratch tasks
shift the mixed capture's task locator.

Older-Bob fixtures (no record keys) are checked in by hand:
record-parse-old-bob.json, record-complete-old-bob.json,
record-targets-old-bob.json.

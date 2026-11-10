# Notebook fixtures

Generated from a real Bob; do not hand-edit the JSON.

- bob: bob 0.5.0
- clock: 2026-11-10 09:00:00, TZ=UTC0, isolated XDG paths, scratch vault only
- vault: area dev; notebook frontmatter and owner catalog follow the
  notebooks contract; dev_nvim and nested dev_nvim_lua contain one
  block-ID note and one ID-less note
- commands: capture-complete (notebook route, parent notes, sections, block
  ID, create directive); capture-parse (ordinary and sub-notes); capture
  --dry-run (existing section, new section, named note, child notes, and
  create-then-use batch); capture-targets

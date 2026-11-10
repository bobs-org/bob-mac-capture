# Notebook fixtures

Generated from a real Bob; do not hand-edit the JSON.

- bob: f2882ea6fc30894c848bafa4a68e4f81b7c148ed
- clock: 2026-11-10 09:00:00, TZ=UTC0, isolated XDG paths, scratch vault only
- vault: area dev; notebook frontmatter and owner catalog follow the
  notebooks contract; dev_nvim and nested dev_nvim_lua contain one
  block-ID note and one ID-less note
- commands: capture-complete (notebook route, parent notes, sections, block
  ID, create directive); capture-parse (ordinary and sub-notes); capture
  --dry-run (existing section, new section, named note, child notes,
  create-then-use batch, and nested-notebook creation); capture-targets

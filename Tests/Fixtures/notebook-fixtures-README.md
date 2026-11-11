# Notebook fixtures

Generated from a real Bob; do not hand-edit the JSON.

```bash
BOB_BIN=/path/to/CARGO_TARGET_DIR/debug/bob BOB_CLI_DIR=/path/to/bob-cli \
  Scripts/generate-notebook-fixtures.sh
```

- bob: 1f4c94571454ed9307094a677f69b31cddc30600
- clock: 2026-11-10 09:00:00, TZ=UTC0, isolated XDG paths, scratch vault only
- vault: area dev; notebook frontmatter and owner catalog follow the
  notebooks contract; dev_nvim and nested dev_nvim_lua contain one
  block-ID note and one ID-less note; dev_empty has no sections and dev_dup
  has two identically named sections
- commands: capture-complete (notebook route, parent notes, sections, block
  ID, create directive, glued and bullet section menus including empty,
  existing, staged, new, clean-create, near-miss, refused, and glued-empty
  rows); capture-parse (ordinary, sub-notes, glued empty, and notebook
  section bullets); capture-rewrite (slash alias); capture --dry-run
  (existing/new/top sections, named note, child notes, grouped notebook
  batch, create-then-use batch, nested creation); capture-targets

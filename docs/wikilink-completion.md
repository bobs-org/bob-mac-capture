---
title: "Mac Capture wikilink completion"
description: "Obsidian wikilink, heading, block, and alias completion in the Bob Mac Capture editor."
---

## Wikilink Completion

Typing an Obsidian wikilink anywhere in the draft — a note (`[[sas`), an embed
(`![[sas`), an alias (`[[Artificial Intelligence|AI`), a heading (`[[sase#Des` or the
same-note `[[#Des`), or a block reference (`[[sase#^goog` or the same-note `[[#^goog`) —
drives completion the same way capture-marker syntax does, keyed off the real caret
position rather than the end of the draft. `bob-cli` owns every part of this: vault
discovery, ranking, and the exact replacement text and byte range; the app only
decodes and presents it.

- **Note completion** (`wikilink_note`) inserts a vault-relative path without `.md`
  (`[[sase]]`), or the canonical `[[path|Alias]]` form when the match came from a
  frontmatter alias — never a bare alias with no path.
- **Heading completion** (`wikilink_heading`) resolves against the capture's own
  destination for `[[#...]]`, a named note for `[[Note#...]]`, or the whole vault for
  `[[##...]]`.
- **Block completion** (`wikilink_block`) works the same way for `[[#^...]]`,
  `[[Note#^...]]`, and vault-wide `[[^^...]]`.
- Accepting a candidate always applies the server's exact byte range and `cursor_after`
  in one step, so the caret lands exactly where typing would have left it — after the
  closing `]]`, mid-heading, or wherever the candidate specifies.

Each completion row shows a compact SF Symbol and context label for what will be
inserted (Note/Heading/Block, alongside Destination/Section/Parent Task/Task Section
rows), a primary line with restrained emphasis on the part of the text
that matched what you typed, and a secondary line with the canonical vault-relative
path, parent task, or `route:block-id` plus small badges — `Alias`, a heading level
like `H2`, a short block preview, `^block-id`, `Add ID`, `N items`, or `Empty`.
Reading tasks (`task_kind` `ref`) draw the `book` symbol in the `^`, `:`,
`+`, `&`, and `!` pickers; the text already arrives without `#ref`.
`^` active tasks no longer use this list; they open the [Active Task Picker](task-pickers.md).
`@route+` task suggestions are grouped as
**Ready to use** followed by **Needs block ID**, preserving Bob's order inside each
group; task-section rows stay a plain ungrouped list. Long paths truncate from the
middle, keeping the filename intact rather than the leading directory. The selected
row's accent-tinted fill uses each result's own semantic color (matching the editor's
highlight palette) and increases its opacity automatically under Increase Contrast.
VoiceOver announces the context, the count of results, and each row's full
context/name/path/badge description before "double-tap to insert."

Note metadata — paths, stems, frontmatter aliases, heading text, and block-id previews
— is read directly by `bob` from the local vault to build these candidates. The app
never logs it, writes it to `UserDefaults`, or includes it in a notification, signpost,
or Diagnostics entry; see [Permissions](permissions.md#privacy).

Note metadata stays local: paths, stems, aliases, headings, and block previews are read by `bob` from the vault and are never logged, persisted, or included in notifications or diagnostics. Disk and memory rules are in [Permissions](permissions.md). Empty candidate lists and `Link completion warning:` recovery are in [Fix Mac Capture when bob is not resolved](https://bobs-org.github.io/guides/fix-mac-capture-bob-resolution/).

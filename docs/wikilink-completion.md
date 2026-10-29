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
## Task wikilinks (`((`)

Typing `((` anywhere free text is allowed in a capture draft — task text,
sub-bullets, bulk-draft lines — opens the Task Wikilink picker over every
task in the vault, including tasks with no block ID yet and completed
history. Choosing a task replaces the `((query` token with a plain Obsidian
block link such as `[[sase_cleanup#^no-idle]]`; the draft never stores the
`((` itself. `bob` owns the trigger grammar, the candidate list and order,
the replacement bytes, and the block-ID write; the app only filters locally,
renders, and splices what `bob` returns.

The card groups an empty filter in `bob`'s order — This note, In Progress,
Next, one section per note, then Completed history — and a non-empty filter
becomes one ranked flat list with open matches ahead of completed ones at
equal score. Rows show the status glyph, the task text (`` `code` `` on a
faint fill, `[[links]]` and Markdown `[labels](url)` accent-tinted by their
label), and a trailing locator drawn as the link it will insert (`note` in
the wikilink target color, `#^` in the delimiter color, `id` in the
block-ID color). ID-less rows show the note plus an Add ID badge; guarded
rows are dimmed with `bob`'s reason; completed rows carry a quiet
Done / Cancelled capsule. The detail strip names the exact insert
(`↩ inserts [[note#^id]]`, or `↩ names it ^suggestion in note.md, then
links it`), and the footer reads `↑↓ Move · ↩ Insert link · ⌘↩ Insert &
Capture · ⌃↩ Capture & Open · esc Clear/Cancel`.

Accepting an ID-less row opens the Add block ID prompt in Task Wikilink
mode: the field is prefilled with `bob`'s first suggestion fully selected,
the other suggestions are clickable chips, and a live line shows the
`[[note#^typed]]` link the prompt will insert. Return adds the ID and
links, Command-Return adds it and captures, and Escape returns to the
picker with the filter intact.

Keys match the shared picker contract: Return inserts, Command-Return
inserts and captures, Control-Return inserts, captures, and opens, Escape
clears a non-empty filter or cancels, and Backspace on an empty filter
deletes the trigger back to one literal `(`.

Unlike `[[^^` vault block search — which finds existing block IDs anywhere
in the vault — `((` lists tasks (including ID-less ones that `[[^^` can
never offer) and can name a block ID for the chosen task before linking.

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

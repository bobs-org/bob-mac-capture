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

## Pull-In reason LINK band

Typing `[[` in a successor Pull-In Cancel reason opens a `LINK` band in the
`USED BEFORE` band's slot, answered by `bob capture-complete --links-only`
(plus `--source-note <task note>` when the row carries one) instead of the
capture draft's own completion. The app debounces 60–80 ms per text or caret
change, keeps the previous rows visible while a request is in flight, and
drops stale replies by generation. An older bob without `--links-only`
fails open for the session: plain typing and the `USED BEFORE` band keep
working, and any other error means no band.

Rows render with the same completion rows as draft wikilinks (Note, Heading,
Block) at 22pt with path metadata, and a detail strip names the exact
`[[…]]` link Return inserts. Up/Down and Control-N/Control-P move without
wrapping (the bottom row bumps), Return and Tab insert bob's replacement at
bob's byte range through the field editor — one undo step, caret at
`cursor_after` — and keep the reason open. Return with no rows closes the
band without confirming the Pull-In — as does Return on a stale caret, edited
text, or a missing editor — Tab with no rows passes through to the host, and
Esc / Control-[ close the band only. Clicking a row inserts it without
confirming. The event-note editor stays excluded: it escapes `[`, so a
completed link would be corrupted.

### Task links (`((`)

Typing `((` in the same reason opens the band's tasks mode, headed
`LINK · tasks · k of n` and requested as `capture-complete --links-only
--task-links`. bob returns `wikilink_task` rows in its order (This note, In
Progress, Next, open, then history). Each row shows a status glyph, the task
text, a group capsule on the first row of each run (empty `((` only), and the
link it will insert: target, `#^`, then the ID, or `⊕` and bob's first
suggestion for an ID-less task. Return or Tab on an identified row splices
bob's `[[target#^id]]` over the `((query` bytes as one undo step. The Pull-In
row's own task, and any row bob guards, dims, shows its reason in the detail
strip (`The task this prompt is about`), and stays put on Return.

Return or Tab on an ID-less row turns the band into a NAME stage: the
reusable block ID field, focused and prefilled with bob's first suggestion
(Tab and the arrows cycle the rest), above `↵ adds ^id, then links
[[target#^id]]`. Return runs `bob capture-task-id --note-path --task-ref
--block-id`, with `--allow-closed` for Done and Cancelled rows. That is the
only vault write the band causes, and only on that Return. It then splices
bob's `wikilink_replacement`, returns focus to the reason field, and closes
the band. Esc returns to the list with the filter intact, and focus moving
into the ID field never confirms or restores the Pull-In. The reason is not
edited before the write succeeds; if it changed meanwhile, nothing is
inserted, and a fresh `((` finds the task identified. A failed write keeps
the stage open with bob's reason. A bob without `--task-links` keeps `((`
literal and `[[` working.

Each completion row shows a compact SF Symbol and context label for what will be
inserted (Note/Heading/Block, alongside Destination/Section/Parent Task/Drawer
rows), a primary line with restrained emphasis on the part of the text
that matched what you typed, and a secondary line with the canonical vault-relative
path, parent task, or `route:block-id` plus small badges — `Alias`, a heading level
like `H2`, a short block preview, `^block-id`, `Add ID`, `N links`, or `Empty`.
## Task wikilinks (`((`)

Typing `((` anywhere free text is allowed in a capture draft — task text,
sub-bullets, bulk-draft lines — opens the Task Wikilink picker over every
task in the vault, including tasks with no block ID yet and completed
history. Choosing a task replaces the `((query` token with a plain Obsidian
block link such as `[[sase_cleanup#^no-idle]]`; the draft never stores the
`((` itself. `bob` owns the trigger grammar, the candidate list and order,
the replacement bytes, and the block-ID write; the app only filters locally,
renders, and splices what `bob` returns.
The picker opens because `bob capture-parse` marks the `((` token with task
wikilink spans, which the app uses to request completion.

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
group; `drawer` rows are painted by their own menu (On this task, Recent, and a New
drawer row). Long paths truncate from the
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

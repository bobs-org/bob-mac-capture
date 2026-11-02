---
title: "Mac Capture lists"
description: "How Bob Mac Capture presents a lone @file header over bullets: the first bullet, task-ID prompts on nested lines, and the grouped preview."
---

A line that holds only `@file` or `@file#section`, followed by bullets, is a list: Bob files each first-level bullet as its own task (or section note) in that file, exactly as `<bullet> @file` would. Bob owns the grammar and every write ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)). The app decodes what Bob reports, applies the edits Bob returns, and paints. The task-ID rules are in [Capture syntax](https://bobs-org.github.io/reference/capture-syntax/); this page covers what the panel does with them. Subprocess fields and older-bob behavior are in [Protocol](protocol.md).

## Starting a list

- A lone header with no bullet yet reports the `list_item` need. The panel keeps the preview calm and shows `Add a bullet under the header — Shift-Return starts one` instead of a refusal.
- Shift-Return or Option-Return with the caret at the end of that header inserts `\n- `, so the next keystroke is the first bullet. It acts only on the header line of the item Bob's parse of the current draft reports as needing a `list_item`, and not when a row already sits under the header. Anywhere else the key inserts a plain newline. Ctrl-J already starts an indentation-aware `- ` row.

## Task IDs on bullets

A trailing ` :` or ` ^` on a bullet, or on one of its nested lines, opens the [Project task](task-pickers.md#block-id-picker) prompt, with Bob's suggestions drawn from the owning task's text. A section list opens no prompt.

- Bob sends `block_id.owner_line` (the owning task's line) and `block_id.splice`. Accepting writes `before + ID + after` over the splice's range, so a prompt opened on a nested line puts the ID on the owner's line, replaces an ID already there, and leaves the caret where you were typing.
- When the owner is on another line, a header row names it (`ID for ‘Fix flaky gkeep test’`, with what accepting does), the detail strip leads with the same words, and the announcement reads `Inserted :fix-flaky-gkeep on ‘Fix flaky gkeep test’`.
- Project-note task bullets behave the same way.

## Preview

Bob reports each bullet as its own result with an additive `list` object: `kind` (`tasks` or `notes`), `route`, `section`, `header_line`, `position`, and `count`. The preview stacks one list's results under a single capsule, `3 tasks → dev.md` or `2 notes → dev.md · ideas`, without dividers between them. VoiceOver reads it as `List of 3 tasks, filed to dev.md`. A batch with two lists gets two capsules, and a result with no `list` object keeps its divider and shows no capsule.

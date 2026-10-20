---
title: "Mac Capture pickers"
description: "Every Bob Mac Capture picker and the shared card lifecycle: browse, insert, and capture from the keyboard."
---

Pickers browse what `bob` returns and insert exactly its replacement range. One large elevated card serves every context: a filter bar with a scope token, the task count, a scrollable list with pinned headers, a detail strip with the insert outcome, and key-hint chips. Empty states explain what a task needs to appear. Filtering is local (spaces are AND terms); the snapshot, ordering, replacements, and intents are all `bob`'s.

- [Task pickers](task-pickers.md): Task Link (`:`), Go To (`/`), Parent Task (`@file+` and vault `+`), Active Task (`^`), and Block ID (`@route:` / `@route^`), plus Name Pomodoro and named-start lists.
- [Relationship pickers](relationship-pickers.md): Dependency (`&`), Blocks (`*`), Complete (`!`), and Relations (`~` / `~~`).

Cards that only pick a destination or an ID never capture on their own: Return inserts and returns to the editor, Shift-Return variants stay in the draft where documented, and Command-Return / Control-Return capture with the inserted result. ID-less rows open the Add block ID prompt, which names the task through `bob capture-task-id` and splices the returned canonical ID; Name Pomodoro rows name through `bob capture-pomodoro-name`. Cancel and every failure keep the draft unchanged. Rendered results are in [Capture previews](capture-previews.md).

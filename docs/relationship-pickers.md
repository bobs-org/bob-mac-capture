---
title: "Mac Capture relationship pickers"
description: "Dependency, Blocks, and Complete pickers in Bob Mac Capture."
---

Relationship pickers consume `bob`'s additive contract and never parse quoted note components themselves: `bob` sends the decoded query, the owner, exact paths, groups, hidden and already-added flags, disabled reasons, and the backend-formatted replacement, which is empty for ID-less and guarded rows. The shared card lifecycle is in [Pickers](pickers.md); rendered rows are in [Capture previews](capture-previews.md).

## Dependency Picker

## Dependency Picker

Typing `&` at the start of an item or after whitespace opens the Dependency
Picker (`task_dependency` context), the same card with scope `&` and caption
Depends On. It consumes Bob's additive contract and never parses quoted note
components itself: Bob sends the decoded `query`, the lexical `owner`
(`new_task` / `existing_task`), the exact `note_path` (extension included, case
and Unicode preserved), the display `locator`, the `group`, `hidden`,
`already_dependency`, and `disabled_reason` per row, plus a Bob-authored
`replacement` (`&note:id`, quoted when the locator needs it) that is empty for
ID-less and guarded rows.

The header names the owner and direction: **⛓ Exercise depends on…** with
`body.md ^excercise · In Progress` beneath, or **⛓ “Buy Groceries!” depends
on…** for a new-task owner (empty new-task text is **New task depends on…**).
An older Bob that omits owner text falls back to `@body+excercise`. For an
ownerless leading `&`, the title stays Choose a prerequisite and the subtitle
is "Then type the task, or + for an existing one" — choosing first stays
allowed. No word appears twice in the header. With an empty filter rows group
in Bob's order: **This note** (`in_this_note`) first, then In Progress, Next,
one section per note (`note_path`), then a separate Completed history section
(selecting there never blocks); `#hide` rows render subdued and sort last
within their section. A non-empty filter replaces the groups with one ranked
flat list. Already-added rows show Already added and accepting one changes
nothing; guarded rows carry Bob's explanation and neither insert nor open the
ID flow.

When `capture-parse` reports `dependency_target` with no open picker (a
complete `&foo:bar` and no owner yet), the app skips the doomed live dry run
and shows a calm secondary hint instead of a red preview error: **⛓ What
depends on “Buy shoes”? Type a new task, or + for an existing one.** Names
come from `&`/`*` rows the user accepted; a token typed by hand falls back to
`foo:bar`. The other shapes are **🧱 What blocks “Do cleanup tasks”? Type a
new task, or + for an existing one** and **Type the task between “Buy shoes”
and “Do cleanup tasks”, or + for an existing one**.

Return (or Tab) replaces only Bob's range with the replacement and returns to
the editor; at a terminal token one separating space is left for typing another
`&`. Command-Return inserts then captures only when the dependent is complete;
Control-Return also opens the reported notes when the dependent is complete;
with no dependent yet it keeps the draft open ("Add task text or @note+id,
then capture"). Shift-Return has no start-session behavior on this source.
Escape restores the draft/caret and shows the Choose dependency chip; Backspace
on an empty filter removes the `&` token.

Rows without an ID show `locator:` plus a dim suggestion; accepting one opens
the Add block ID prompt ("Add ID and use task — edits that note now") in
dependency mode, calling `bob capture-task-id --note-path` with the exact path
(passing `--allow-closed` for Done/Cancelled history rows, which never
reopens them) and splicing Bob's `dependency_replacement` verbatim. Escape
returns to the picker with the filter intact; assignment failure inserts
nothing. The prompt buttons read Add ID & Use / Add ID & Capture.

Dependency Picker keys: Return/Tab Insert, Command-Return Insert & Capture,
Control-Return Insert, Capture & Open when the dependent is complete.

## Blocks Picker

## Blocks Picker

Typing `*` in Bob's valid blocked-task position opens the shared dependency
picker in the Blocks direction (`blocked_task` context): scope `*`, caption
Blocks, and the header **🧱 Exercise blocks…** with the owner location line,
**🧱 “Buy Groceries!” blocks…** for a new-task owner, or **Choose a task to
block** when there is no owner yet. Bob supplies the query, owner, candidates,
`already_blocked`, disabled reasons, and backend-formatted `*note:id`
replacements. The action line reads
`↩ inserts *job:cleanup · space adds another *`; rows already on the owner's
Depends-On line say **Already blocked**. Disabled explanations appear verbatim
from Bob.

The partial `X *` need shows **Pick a task to block — press Tab to browse**.
Return or Tab inserts Bob's replacement, Command-Return inserts then captures
when the owner is complete, Control-Return also opens the reported notes, and Backspace on an empty filter removes the `*`
token. A line-initial `*` stays a Markdown bullet placeholder. ID-less rows use
`capture-task-id --note-path` and splice `blocked_task_replacement`; older Bob
shows **This Bob is too old for blocked-task picks. Update Bob first.**

Blocks Picker keys: Return/Tab Insert, Command-Return Insert & Capture,
Control-Return Insert, Capture & Open when the owner is complete.

## Complete Picker

## Complete Picker

Typing `!` at the start of an item opens the Complete picker
(`task_complete` context), the same card with scope `!` and caption
Complete. When `capture-parse` reports `task_complete` in `needs`, the app
skips the doomed live dry run and shows "Pick a task to complete — press Tab
to browse".

Bob lists every open task (Ready, Blocked, Next, In Progress) vault-wide,
today first. With an empty filter rows group in Bob's order: one section per
today Pomodoro (the running entry with the pink NOW pill, completed entries
recent-first with 🍅, their time range, and a Done capsule, queued entries
with UP NEXT), then "In today's note", In Progress, Next, and one section
per note (`note_path` with a `doc` icon). While filtering, two ranked
sections appear with their headers: Today then All open tasks. Rows show the
status glyph (Blocked is `pause.circle`), text, and locator (note in accent,
`:` , ID in indigo), a `🍅 N` capsule when the task was in two or more
Pomodoros today, and a schedule capsule when present. Disabled rows stay
visible with their reason badge and no insertion; recurring rows sort last.
The detail strip renders Bob's action line for the selected row
(`Inserts !sase:fix-flaky — completes it [*] → [x]`, with a Blocked variant
and the disabled reason).

Return (or Tab) inserts Bob's `!note:block-id`; Shift-Return inserts, appends
a blank line plus `!`, and the fresh picker opens with the just-picked task
marked "Already in this draft" for bulk completions; Command-Return inserts,
then captures; Control-Return inserts, captures, and opens Bob's reported notes.
With an empty filter, Bob's continuation keys `!` and `[`
close the picker and type the key, so `!!` falls back to prose and `![`
hands off to embed completion. Escape and Backspace behave as in `:`.

ID-less rows open the Add block ID prompt via `capture-task-id --note-path`
and splice Bob's `complete_replacement` verbatim; Swift never builds the
token. The prompt previews `!<locator>:<id>` from Bob's candidate locator,
never the file name. The buttons read Add ID & Insert and Add ID & Complete.

Complete Picker keys: Return/Tab Insert, Command-Return Insert & Capture,
Control-Return Insert, Capture & Open.

Preview rows, notifications, and the successor choice card are in [Capture previews](capture-previews.md).

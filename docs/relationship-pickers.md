---
title: "Mac Capture relationship pickers"
description: "Dependency, Blocks, Complete, and Relation pickers in Bob Mac Capture."
---

Relationship pickers consume `bob`'s additive contract and never parse quoted note components themselves: `bob` sends the decoded query, the owner, exact paths, groups, hidden and already-added flags, disabled reasons, and the backend-formatted replacement, which is empty for ID-less and guarded rows. The shared card lifecycle is in [Pickers](pickers.md); rendered rows are in [Capture previews](capture-previews.md).

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

## Relation Picker

Typing `~` in Bob's valid relation position opens the Links To picker
(`relation_to` context): scope `~`, caption Links To, and the header
**🪢 “Owner” links to…** (or **🪢 Choose a task to link to…** when there is
no owner yet). The subtitle is **any task · ~ flips direction**. Typing `~`
anywhere in the filter live-flips Links To ↔ Linked From in place: to
Linked From (`relation_from`) it shows scope `~~`, caption Linked From, and
the header **🪢 Choose a task that will link to “Owner”**. The filter keeps
its text and the typed `~` never enters it; repeats are ignored. Auto-open
is never suppressed. Backspace on an empty `~~` filter flips back by
removing one `~`; Backspace on empty-filter `~` removes the token.

Bob supplies `already_linked`, `existing_label`, `also_prerequisite`,
disabled reasons, and backend-formatted `~note:id` / `~~note:id`
replacements. Already-linked rows show **Already linked · follow-up of** when Bob sends
an existing label. Prerequisite-too rows show **Prerequisite too**. Archived rows (locator
`done/` or `/archive`) show **Archived**. Done history rows show **Done**.
Disabled explanations appear verbatim from Bob (`its LINKS line is malformed`,
`read-only note`, `archived tasks can't get an id`).

The action line reads `↩ link · ⇧↩ link with a relation · ~ flips direction`.
Shift-Return inserts the token and opens the relation card. Typing `|` after a
relation token also opens the card; Bob removes any spaces or tabs before the
pipe through the rewrite lane, and Undo restores the typed ` |`. The card keeps
its query field separate from the highlighted label and filters the catalog
fetched when it opens. Ctrl-N/P and Down/Up move the highlight, wrapping through
the field. Tab inserts the selected label, or the top match when nothing is
selected. Return inserts the selected label, or uses Bob's fresh typed-label
replacement; with an empty field it removes the pipe and leaves the bare relation
token. Shift-Tab is consumed. Escape returns to the unchanged draft. Command-Return
inserts then captures when the owner is complete;
Control-Return also opens the reported notes. The `~` / `~~` sigil uses a mint
knot accent, distinct from the grey Pomodoro-drop `~`. Relation labels render
muted italic; the `|` separator is muted. When Bob's `relations.cancel_labels`
lists a row, the card shows a `circle.slash` `cancels` capsule. Selecting or
typing that label dims the live-sentence source as `⊘ {S} — {label} → {T}`
and puts Bob's `relation_cancel.message` in the slot the `||` warning uses
(⊘ tint when the verdict is `cancels`, muted for `Already Cancelled · link
only` / `Stays Done · link only`). Inverse labels show Bob's muted `hint`.
Disabled recurring and new-task rows keep Bob's `disabled_reason` and stay
dimmed. VoiceOver names the source as `Cancels Sell stocks!`. Older Bob
omits the fields and the card stays as it is.

The partial `X ~` need shows **Pick a task to link — press Tab to browse**.
A `|label` field shows **Type a relation label, or pick a suggestion**.
Owner-mode `+` copy uses `picker.relationship.relations[]`
(**🪢 Which task links to “Target”?**).

ID-less rows use `capture-task-id --note-path` and splice
`relation_to_replacement` / `relation_from_replacement`; older Bob shows
**This Bob is too old for ~ links. Update Bob first.** The prompt buttons
read Add ID & Use / Add ID & Capture.

Relation Picker keys: Return/Tab Link, Shift-Return Link with a relation
(opens the relation card), tilde Flip direction, Command-Return Insert & Capture,
Control-Return Insert, Capture & Open when the owner is complete.

Relation card keys: Ctrl-N/Down next, Ctrl-P/Up previous, Tab accept, Return
accept selected or typed label, Ctrl-D hide what Return would insert (or toggle
one-off), typed `|` one-off on, Ctrl-H Hidden section, Ctrl-R rename the label
everywhere with a live dry-run preview and merge confirm, Escape back (leaving
rename mode first). The card
opens in one-off mode on a `||` token. Hidden labels live in the Hidden section
and stay insertable; a hide or unhide keeps its row as a ghost with ⌃D undo
until the query changes, and a failed write restores the row with Bob's message.
After a rename the card selects the new label and rewrites matching relations
in the open draft.
See [Keyboard](keyboard.md#relation-card-keys)
for the complete key table.

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

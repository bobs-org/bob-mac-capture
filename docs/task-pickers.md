---
title: "Mac Capture task pickers"
description: "Task Link, Go To, Parent Task, Active Task, and Block ID pickers in Bob Mac Capture."
---

Every picker here browses open tasks and inserts exactly what `bob` returns. `bob` supplies one snapshot per context (rows, ranges, replacements, intents); the app filters locally, applies the server-provided byte range and `cursor_after`, and never synthesizes grammar. Return (or Tab) inserts, Command-Return inserts and captures, Control-Return inserts, captures, and opens the reported notes. Escape clears a non-empty filter first, then cancels to a reopen chip; Backspace on an empty filter removes the trigger token. While `capture-parse` reports a picker need, the app skips the doomed live dry run and shows a calm browse hint instead of a red error. What each insert previews and captures is in [Capture previews](capture-previews.md); the card is shared with the [relationship pickers](relationship-pickers.md).

## Active Task Picker

  Typing `^` as the whole capture item opens the Active Task Picker (`active_task`
  context), a modal mode of the capture panel — not a second window. Bob supplies one
  full snapshot (every In Progress and Next task with
  a block ID, in Bob's ledger order); the app filters that snapshot locally with
  a fuzzy matcher in `CaptureCore`
  so each keystroke is instant and flicker-free, and filter text never touches the
  draft. Local filtering is a deliberate presentation-only responsibility, the same
  precedent as the locally ranked `capture-targets` route cache. The picker auto-opens
  only when the edit writes the `^` trigger before Bob's replacement range, including
  a paste or fast typing since the last settled analysis. Backspace, Delete, typing
  inside an existing `route:block-id`, and caret-only moves show a compact
  "Browse active tasks ⇥" chip instead. Escape suppresses auto-open for that token
  while the chip offers a one-key reopen. Reshowing the panel with the picker open
  also reopens it. Fast typing is safe: text typed before the picker appears seeds
  the filter.
  Return (or Tab, or a click) inserts exactly Bob's `route:block-id` into Bob's range
  and returns to the editor, keeping any typed `#name`/`=<X>`/`=x` suffix — the app
  never synthesizes that grammar, you type it after the insert. Command-Return inserts
  and captures in one step; Control-Return inserts, captures, and opens the reported
  notes in Obsidian. An exact `route:block-id` never opens anything. When
  `capture-parse` reports `active_task` in `needs`, the app skips the doomed live dry
  run and shows "Pick an active task — press Tab to browse" instead of red
  incomplete-marker errors. Cached route completion never intercepts `^`, and the
  `active_task_route`/`active_task_block_id` spans reuse the route and block-ID
  highlight colors. The inline completion list is unchanged for every other context.
  Active Task Picker keys: Return/Tab Insert, Command-Return Insert & Capture,
  Control-Return Insert, Capture & Open.
- While the Active Task Picker is open, printable keys edit the filter field natively
  (as do Cmd-A/C/V/X/Z, Ctrl-A/E, and Left/Right). Return/Tab inserts the selected
  task and returns to the editor; Command-Return inserts and captures; Control-Return
  inserts, captures, and opens the reported notes;
  Shift/Option-Return and Shift-Tab are consumed. Down/Ctrl-N/Ctrl-J and Up/Ctrl-P/Ctrl-K
  move (wrapping); Page Up/Page Down move one page; Cmd-Up/Home and Cmd-Down/End jump
  to the first/last row. Escape clears a non-empty filter, then cancels (draft
  unchanged, caret restored, auto-open suppressed, chip shown). Backspace on an empty
  filter removes the `^` trigger and its fragment. Ctrl-S is consumed; Ctrl-C still
  stashes the draft and closes. While the chip is visible, Tab, Down, and Ctrl-N reopen
  the picker and Escape hides the chip.

## Task Link Picker

## Task Link Picker

Typing `:` as the whole capture item opens the Task Link Picker (`task_link`
context), the same card as `^` with scope `:` and caption Open Tasks. When
`capture-parse` reports `task_link` in `needs`, the app skips the doomed live dry
run and shows "Pick any open task — press Tab to browse".

Bob lists every open (not done or canceled) task in area, project, and inbox
notes. With an empty filter tasks group in Bob's order: one section per queued
Pomodoro, then In Progress, Next, then one section per note
(`route.md` with its Inbox/Area/Project subtitle). The app filters locally with
spaces as AND terms; a non-empty filter replaces the groups with one ranked flat
list. Rows show a schedule capsule (`calendar` glyph) when Bob sends one and a
Pomodoro chip in the filtered view; the detail strip shows the insert action and,
when linking pulls a future schedule forward,
`Scheduled Oct 3 — linking pulls it forward`.

Return (or Tab) replaces the `:` query with `@route:block-id`; Shift-Return
inserts `@route:block-id=` so the live preview shows the start before Return
captures; Command-Return inserts then captures; Control-Return inserts, captures,
and opens the reported notes. Escape clears the filter, then
cancels to the reopen chip; Backspace on an empty filter removes the `:` token.

Tasks without an ID show `route:` plus a dim `plus.circle` suggestion; accepting
one opens the Add block ID prompt in link mode, prefilled with the first
suggestion (fully selected), with clickable suggestion chips and Tab / Shift-Tab
cycling, a live `Inserts @route:<typed>[=]` line, and buttons Add ID & Link /
Add ID & Start / Add ID & Capture. Return names the task via
`bob capture-task-id` then splices the link (appending `=` for Start, submitting
for Capture); failure keeps the prompt open with Bob's error; Escape returns to
the picker with the filter intact.

Bulk drafts work: each blank-line-separated item is judged alone.

Task Link Picker keys: Return/Tab Link, Shift-Return Link & Start,
Command-Return Link & Capture, Control-Return Link, Capture & Open, Escape Clear/Cancel, Backspace on empty filter
removes `:`. In the link-mode Add block ID prompt, Tab / Shift-Tab cycle
suggestions.

## Go To Picker

## Go To Picker

Typing `/` as the whole capture draft opens the Go To picker (`task_goto`
context), the same card as `:` with scope `/` and caption Go To. When
`capture-parse` reports `task_goto` in `needs`, the app skips the doomed live
dry run and shows "Pick a task to open — press Tab to browse".

Bob lists the same open tasks as `:`, in the same order. Every row is
selectable, including ID-less ones: they show `note.md:line` with no
`plus.circle` suggestion and no Add block ID prompt. The detail strip reads
"↩ Opens note.md at ^id" or "↩ Opens note.md at line N". A scheduled date
still shows as context; there is no "pulls it forward" warning. Accepting a
row dispatches `obsidian://bob-goto-task` (provided by bob-navigation-hotkeys)
and, once that open succeeds, hides the panel and discards the draft. Nothing
is minted, stamped, linked, walked, or captured. A failed dispatch keeps the
picker open with "Couldn't open Obsidian".

Return, Tab, click, Command-Return, and Control-Return all Go To the selected row.
Shift-Return and Option-Return are consumed. Escape clears a non-empty
filter, then cancels to the reopen chip; Backspace on an empty filter removes
the `/` token and the idle agenda returns. Control-C on a Go To draft
discards it instead of pushing it to the canceled-draft stash.

Go To Picker keys: Return/Tab/Command-Return/Control-Return Go To, Shift-Return consumed,
Escape Clear/Cancel, Backspace on empty filter removes `/`, Control-C
discards.

## Parent Task Picker

## Parent Task Picker

Typing `@file+` opens the parent-task picker scoped to that note (`task` context
with Bob's additive `picker` descriptor, `scope: note`). Typing `+` at the start
of an otherwise empty item, or after a space at the end of a capture line, opens
the same card across capture notes (`task_parent`, `scope: vault`). Choosing a
task inserts `@file+id`. An older Bob that returns `task` without the descriptor
keeps the inline parent-task list.

The card uses the same picker lifecycle as `:` and `^`. Scope capsules read
`@cash+ · cash.md` or `+ · All capture notes`. Vault empty-query rows keep the
colon groups (queued Pomodoros, In Progress, Next, notes). Scoped empty-query
rows keep Bob's document order. A nonempty filter is one ranked list with spaces
as AND terms. Rows never show a Link & Start action or a schedule pull-forward
warning. The detail strip always says **Inserts @cash+goog-exit**.

When `capture-parse` reports `task_parent` in `needs`, the app skips the doomed
live dry run and shows "Choose a task to append to — press Tab to browse".
Inside a relationship draft Bob sends `picker.relationship`; the picker then
opens in owner mode headed **⛓ Which task depends on “Buy shoes”?** /
**🧱 Which task blocks “Do cleanup tasks”?** /
**Which task depends on “Buy shoes” and blocks “Do cleanup tasks”?**, the
status line and reopen chip read **Choose the task to relate**, and rows Bob
guards (`the prerequisite itself`, cycles, a project's own resident) are
dimmed with that reason as the badge — accepting one only announces it. A
lone whole-item `+` stays a valid +5m Pomodoro adjustment: the picker still
opens, Escape leaves the draft unchanged, and submitting it extends as before.
Bob lists `action_continuation_keys` (`0`–`9` and `+`) only for that dual-use
item. With an empty filter, an unmodified digit or second `+` closes the picker,
inserts that key once, and suppresses reopen so `+2` / `++3` match fast typing.
Scoped and prose-terminal pickers never use that handoff. A quiet footer hint
reads **Type a number or + to adjust; Esc to extend +5m**.

Return/Tab selects the task; Command-Return selects then captures; Control-Return
selects, captures, and opens the reported notes;
Shift-Return is consumed and never appends `=`. Escape clears a nonempty filter,
then cancels to the reopen chip (**Select a parent task** / **Append to a
task**). Backspace on an empty filter uses Bob's `trigger_removal_range`: it
deletes a vault `+query` token, or removes scoped `+query` while leaving
`@route`. Exact identified `@cash+goog-exit` does not auto-open; Tab or the chip
still browses.

ID-less rows open Add block ID with suggestion cycling and a live
`Inserts @route+typed` line. Vault success requires Bob's `parent_replacement`;
if that field is absent the prompt stays open and asks to update Bob. Scoped
success inserts the returned ID into the ID-only range. Buttons read Add ID &
Select / Add ID & Capture.

Parent Task Picker keys: Return/Tab Select Task, Command-Return Select &
Capture, Control-Return Select, Capture & Open, Escape Clear/Cancel, Backspace
on empty filter removes Bob's trigger range. In the card-mode Add block ID
prompt, Tab / Shift-Tab cycle suggestions.

## Block ID Picker

Typing the right-hand side of `@route:` or `@route^` anywhere those markers are
  valid opens the Block ID Picker (`pomodoro_block_id` / `task_block_id` contexts),
  and typing a trailing ` :` / ` ^` on a project-note bullet opens the Project task
  picker (`project_task_block_id` context),
  the same large, fuzzy, keyboard-first picker language as `^`, and never the inline
  list. Bob decides the intent and the app presents it: a marker-only `@route:` item
  gets a Link picker that browses the note's linkable tasks grouped by the note's own
  headings; every new-ID position (`@route^`, `@route:` on an item with text, either
  marker followed by the project-note `+`, or a project-task ` :` / ` ^` token) gets a New ID composer with Bob's
  suggestions from the task text, live availability against every ID already in the
  note, a one-key "next free" alternative when an ID is taken, and similar existing
  IDs for naming consistency. Bob supplies one snapshot (intent, candidates, every
  used ID with what uses it, suggestions, the marker token range, and the ID grammar
  as a one-character regex plus a human description); the app only filters locally,
  checks exact case-sensitive membership in Bob's used-ID list, applies Bob's
  character rule, and derives the `-2…-99` next-free variant validated by that rule.
  Live preview after insert remains the final authority. The picker auto-opens only
  on an edit that writes the `:` / `^` separator byte immediately before Bob's ID
  part. “Writes” means that byte was changed since the last settled analysis, so a
  fast `:rea` burst or a paste still counts. Backspace, Delete, and typing inside an
  existing ID do not open the picker; other non-opening edits show the reopen chip.
  The existing Link exact-candidate and Escape-suppression rules still apply, as does
  the New ID rule that the part must be empty or the caret at its end. Reshowing the
  panel with the picker open and pressing Tab on the chip still open the picker. A `task_block_id`
  response without a `block_id` object is treated as no completion. Link refetches the
  full snapshot at the range start when the caret is past it; New ID needs no refetch.
  Accept inserts the row's ID into Bob's range with the stale-draft guard, announces
  `Inserted @route:id`, and runs an `.edit` analysis without completion;
  Command-accept also captures, and a missing selection announces why instead of
  inserting. In the New ID composer the field only ever holds ID characters: typing a
  character outside Bob's allowed set (space, `#`, `=`, `+`, `.`, …) at the end of the
  field commits the typed ID and keeps typing that character in the editor, so `#`
  after a commit opens `pomodoro_name` completion naturally. The Link picker keeps
  `^`'s semantics: spaces separate fuzzy tokens. Backspace on an empty field deletes
  the `:`/`^` separator and the part so route completion resumes. The chip reads
  `Browse <note> tasks ⇥` (Link) or `Suggest an ID for <note> ⇥` (New ID); Tab, Down,
  and Ctrl-N open it and Escape hides it. When `capture-parse` reports `pomodoro_id`
  or `block_id` in `needs`, the app skips the doomed dry run with precedence
  `active_task`, then `pomodoro_id` ("Pick a task or type a new ID — press Tab to
  browse"), then `block_id` ("Type a new block ID — press Tab for suggestions").
  Older Bob binaries that send `pomodoro_block_id` without a `block_id` object get a
  Link picker without the New ID row and without type-through; older Bob never sends
  `task_block_id`, so `@route^` shows no picker there.

### Keys

- Block ID Picker keys. Link matches the Active Task Picker table; New ID adds Space.

  | Key                                        | Link                | New ID                          |
  | ------------------------------------------ | ------------------- | ------------------------------- |
  | Printables, Cmd-A/C/V/X/Z, Ctrl-A/E, ←/→  | Native filter edit  | Native edit; trailing illegal character commits the ID and keeps typing it in the editor (type-through) |
  | Return / keypad Enter, Tab                 | Insert selected row | Insert selected row             |
  | Command-Return                             | Insert, then capture| Insert, then capture            |
  | Shift/Option-Return                        | Consumed (`:` picker uses Shift-Return for Link & Start) | Consumed (`:` picker uses Shift-Return for Link & Start) |
  | Shift-Tab                                  | Consumed            | Consumed                        |
  | Down / Ctrl-N / Ctrl-J, Up / Ctrl-P / Ctrl-K | Move (wrap)       | Move (wrap), skipping status and info rows |
  | Page Up/Down, Home/End, Cmd-Up/Down        | Page / first / last | Page / first / last             |
  | Escape / Ctrl-[                            | Clear filter, else cancel (suppress, show chip) | Same |
  | Backspace on an empty field                | Delete `:` and part; route completion resumes | Delete `:`/`^` and part |
  | Ctrl-S                                     | Consumed            | Consumed                        |
  | Ctrl-C                                     | Stash and close     | Stash and close                 |

### Card

- The picker renders as one large elevated card spanning the full panel width: a
  46pt filter bar (a `^` scope token, the filter field, and a monospaced task
  count), a scrollable list with pinned Pomodoro headers, an 80pt detail strip,
  and key-hint chips in the footer (↑↓ Move · ↩ Insert · ⌘↩ Insert & Capture ·
  ⌃↩ Capture & Open · esc Clear/Cancel; Control-Return drops first in a narrow
  panel). The editor dims to 50% while picking; tapping it cancels.
  With an empty filter, tasks group by Pomodoro entry in Bob's order, each
  header showing its ordinal, name (or "Unnamed Pomodoro"), `HH:MM–HH:MM` time
  range when present, a pink NOW pill for the current entry, and a task count;
  unqueued In Progress and Next tasks follow under their own headers. A
  non-empty filter replaces the groups with one ranked flat list and a small
  pink Pomodoro chip per row. Rows are 34pt single lines: a status glyph
  (orange In Progress, blue Next), proportional text where `` `code` `` spans
  render monospaced on a faint fill and `[[wikilinks]]` render accent-tinted,
  fuzzy matches in semibold accent, and a trailing `route:block-id` locator in
  route/block-ID colors. The detail strip shows the full text (two lines), a
  metadata line (status, note label with its inbox/area/project icon,
  `› section`, Pomodoro wording), and `↩ inserts ^route:block-id`; after the
  first insert it also teaches `#name`, `=`, and `=x`. Empty states explain
  what a task needs to appear, Bob warnings collapse to one orange line
  (`+N more`), and a partial snapshot notes "Showing Bob's matches only". The
  panel grows once when the picker opens and never resizes while filtering; on
  short screens the card keeps a three-row minimum and scrolls. VoiceOver
  announces the open ("Active tasks, N tasks"), match-count changes, and each
  keyboard move; rows expose the full task label as a button, and selection
  and hover fills strengthen under Increase Contrast.

### Per-mode anatomy

- The Block ID Picker reuses that card with per-mode anatomy. The scope token
  names the marker (`@sase:`, `@sase^`) with a Tasks, New ID, or Project note
  caption, plus `· line N` on multi-line drafts; a Project task session shows
  the bare ` :` / ` ^` sigil with a Linked task / Task ID caption and no
  `@route`. Placeholders read
  "Filter sase.md tasks, or type a new ID" (Link) and "Type a new ID for
  sase.md" (New ID). The trailing element is the count for Link ("96 tasks",
  "5 of 96") and a live availability badge capsule for New ID (green
  "Available", orange "Used · line 36", red with Bob's rule wording, secondary
  "113 IDs in use" while empty, "Checked on capture" for project notes), held
  to a fixed width range so the field never jumps while typing. Link groups
  rows under the note's own headings (`#` glyph in the section color, title,
  count; "Top of note" above the first heading); filtering replaces them with
  one ranked flat list that pins an exact block-ID match first and appends a
  trailing New ID row (or a Used status row) for a valid one-token filter.
  Link rows show the status glyph, rich text, a pink Pomodoro chip in filtered
  mode, depth indent, and a trailing `^block-id` locator. New ID rows show a
  green available ID, an orange taken status plus a "Next free" alternative, a
  red invalid status, an unchecked project-note row, accent `sparkles`
  suggestions with availability badges, and up to five dim 28pt "In use" info
  rows with fuzzy highlights (never selectable). Row locators use the session's
  own marker, so a `^` session reads `route^id` and a Project task row reads
  the bare `:id` / `^id`. The detail strip names the
  outcome per row kind — linked task, new task in `▣ sase.md` (or New Next
  task linked into today's Pomodoro, or the new project note, or for a Project
  task the Next task linked into today's Pomodoro / Task in `▣ cash_goog_exit.md`),
  plus `↩ inserts @sase:id` (`↩ inserts :draft-memo` for a Project task) — and
  after the first insert teaches `#name` or `=` (`:` IDs) or `+` for a project
  note (`+#name` picks its Pomodoro; `^` IDs), tracked separately per source.
  Project notes and Project tasks teach no follow-up.
  Empty states cover no linkable tasks, a missing note, no matches, and the
  empty composer. While any picker is open, the marker token being completed
  carries an accent wash in the dimmed editor (`marker_range` for block IDs,
  the `^` token included for `^`). Key hints match `^`; New ID adds
  `␣ Insert & keep typing`, and all hints fit the 620pt minimum width. Link
  budgets 4…11 grouped rows plus headers, New ID budgets a fixed 6; the panel
  grows once on open and never resizes while typing or filtering. VoiceOver
  labels read "Task picker for sase.md" / "New block ID for sase.md", opens
  announce "sase.md tasks, 96 tasks" / "New ID for sase.md, 3 suggestions",
  availability is announced only on category change, keyboard moves announce,
  and status/info rows are static text without the button trait. Fills
  strengthen under Increase Contrast and color is never the only signal:
  badges and rows carry text.

### Sections and Pomodoro names

  Typing `#` immediately after a resolved `@route+block-id` follows the draft's mode:
  while that item has no body text it opens `pomodoro_name` completion for the task
  toggle, and once the item has body text it opens `task_section` completion for that
  task's ALL-CAPS section bullets. A standalone trailing `#` stays the Pomodoro-note
  marker and `@route#` stays note-section completion. Typing `#` immediately after a
  resolved `@route:block-id` — or a bare `@route:#` — opens `pomodoro_name` completion
  for today's open Pomodoros. Colon-Pomodoro (`@route:id#name`) selects or creates a
  named Pomodoro; plus-sub-bullet (`@route+id#section`) keeps its task-section selector
  as soon as body text exists. For
  blank-line-separated drafts, completion still sends the complete draft as one argv
  value; Bob scopes the answer to the item or declaration containing the UTF-8 cursor and
  returns replacement ranges in draft-global byte offsets. See "Wikilink completion" in [Wikilink completion](wikilink-completion.md) for the Obsidian-specific contract and row presentation.

### Tasks without block IDs

In the `@route+` and `@@route+` task contexts, Bob may return open tasks that still lack block IDs.
  Ready tasks stay first and insert in one action. Missing-ID rows replace the completion
  list with an inline **Add block ID** prompt; opening the prompt moves keyboard focus
  into the block-ID field so the ID can be typed immediately, with a highlighted field
  border while it holds focus. Canceling or completing the prompt returns focus to the
  capture editor. The draft remains unchanged while the app calls
  `bob capture-task-id --route ROUTE --task-ref REF --block-id ID --format json`.
  Only a confirmed Bob success splices the returned canonical ID into the saved
  replacement range and reruns preview. Cancel and every error keep the draft unchanged.

### Naming a Pomodoro

In the `pomodoro_name` context, a matching named open Pomodoro stays the default and
  inserts its slug in one action. When Bob would create a new named future Pomodoro
  instead, the first row is an explicit **Create** / **New future Pomodoro** action
  (`creates_pomodoro: true`, canonical name, no ledger `ref`). Accepting it only
  canonicalizes the `@route:id#name` marker, closes completion without opening **Name
  Pomodoro**, restores the editor caret, and reruns live preview; the daily note is not
  mutated until the later `bob capture` transaction creates the placeholder and task
  link together. A create row that would push the plan past its theme cap
  (`plan_themes_after > plan_themes_cap`) carries a red `after/cap` badge
  (e.g. `4/3`). Unnamed and untypeable-name rows (`requires_name: true`, empty
  `replacement`) still replace the completion list with an inline **Name Pomodoro**
  prompt. The two prompts can never both be open. Opening the prompt pre-fills the name
  field from the in-progress completion query (`#deep-work` becomes `DEEP WORK`), moves
  keyboard focus into the name field, and shows a live `Saves as DEEP WORK` hint. The
  draft remains unchanged while the app calls
  `bob capture-pomodoro-name --pomodoro-ref REF --name NAME --format json`. Only a
  confirmed Bob success splices the returned canonical `slug` into the saved replacement
  range, restores the caret after it, and reruns analysis. Cancel and every error keep
  the draft unchanged. The create-future row never calls `capture-pomodoro-name`.

### Starting a named session

In the `pomodoro_start_name` context — the name part of a whole-item
  `=<X>#name` named start, per token inside chains — the inline list is Bob's
  start-aware **Start** list: today's planned placeholders first (the entry a
  bare `=` would start carries `Next up` and a `Next` badge), then a **New
  session** create row for a missing name, then **Again** rows that start a
  new session named like a completed one (`Last ran 0830–0855`), then
  **Name it** rows for unnamed placeholders (which open the same **Name
  Pomodoro** prompt as `pomodoro_name`), and finally the already-running entry
  (`Running 0840–0905`), which can never be the default. Accepting a new row
  announces `NAME will be created and started when captured`; accepting an
  again row announces `Starts a new NAME session when captured`; both only
  splice the slug and the daily note is not mutated until the later `bob
  capture` transaction. The **New session** and **Again** rows carry the same
  red `after/cap` cap badge as the `pomodoro_name` create row when the new
  theme would push the plan past its cap. Typing `=#` opens the list
  immediately and shows the
  calm `Pick a Pomodoro to start, or type a new name` status instead of a
  doomed dry run; a caret on the `=<X>` suffix itself requests nothing. The
  list narrows as you type while the live preview already shows the resolved
  session, and Return starts it. Under a `=#name` field while a session runs,
  Bob adds its additive top-level `override` object (`keeps_ledger` plus the
  running session) and the list reads as a swap picker: the status becomes
  `Pick a Pomodoro to take over CAPTURE's 0920–0945` (or
  `Pick a Pomodoro to start now · CAPTURE returns to first future` with a
  fresh `=<X>#` timing), open rows read `Takes over 0920–0945`, and the
  running row keeps `Running 0920–0945` while teaching
  `Already running — = restarts it; pick another Pomodoro to swap in`
  (`Restarts it now` with fresh timing). The swap-picker status and rows appear
  as soon as `=#` or `=3#` is typed while a session runs, before a name is entered.
  Under a plain `=#` the running row now
  teaches `Already running. Restart it with =, or close it first with x.`
  An older Bob that reports no
  `pomodoro_start_name` context offers no rows there; the panel simply shows
  no completion until Bob is upgraded.

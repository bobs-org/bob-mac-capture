---
title: "Mac Capture event notes"
description: "Open a private event note from any capture draft: pick an event, edit with Bob's highlights, save through bob gcal note."
---

Event note mode writes a [private event note](https://bobs-org.github.io/gcal-notes/)
— Bob-only `@route`, `#off`/`#on`, buffer, and prose lines for a Google Calendar
event you cannot edit — from inside Bob Mac Capture. Bob owns parsing, validation,
precedence, and vault writes; the app owns the picker, the editor, and process
orchestration ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)).

## Entry routes

- **Command-E** from any capture draft, empty or not. Control-E keeps line motion.
- **Event Note…** in the menu-bar status menu, via the existing coordinator (a hidden
  capture draft is preserved; Refs stays hidden).
- **Calendar row action.** Each agenda Calendar row with a calendar URL carries a
  focusable Event note action; Command-E while that action is focused opens that
  event's URL directly. A row without a URL offers the picker instead of guessing by
  title; an ambiguous URL shows Bob's candidates for explicit selection.

Command-E works with a nonempty draft. The real capture editor stays mounted and
retained underneath — text, selection, scroll position, and undo manager intact —
with capture editing suspended, not saved or rewritten. Exit restores its first
responder.

When the installed `bob` has no `gcal note` support, Command-E reports
"Event notes need a newer bob" and the status-menu item hides until Bob changes or
is rechecked.

## Picker

The picker lists Bob's `gcal note -l -a` events grouped by day (Today, Tomorrow, then
formatted dates), ordered by Bob's returned start. Rows show time, title, organizer
(or calendar fallback), Yes / Maybe / Awaiting-reply chips, a recurring marker, and
the noted summary in the event's root hue. Filtering is local: the filter field
never submits or chooses. Selection is an opaque calendar/event identity — never
matched by title.

| Key | Action |
| --- | --- |
| Control-N / Control-P, Up / Down | Move the selection (scrolls into view) |
| Return / click | Open the selected event |
| Escape | Return to the unchanged capture draft |

## Identity and scope

A recurring match offers **This event** and **All events**; one-off events offer only
This event. Each scope keeps its own unsaved draft while the mode is open, so
switching scope never overwrites the other scope's text. Invalid drafts and Bob's
errors are preserved for correction. A new blank editor first shows the show
response's effective preview — no empty save occurs.

## Editor keys

| Key | Action |
| --- | --- |
| Return | Save the current editor text (repeat presses are consumed; one mutation at a time) |
| Shift-Return | Insert a newline |
| Command-Delete | Clear the selected saved scope (never an inherited series note from an absent occurrence scope) |
| Control-Option-S | Toggle This event / All events (recurring scope only; Tab stays focus traversal) |
| Escape | Back to the picker, keeping this session's per-scope drafts; Escape again returns to capture |
| Command-Z | Undo the last successful mutation while its record exists, from picker or editor; otherwise the editor's own text undo |

The footer reads `Only in Bob · This event` (or `All events`) and
`⏎ Save · ⇧⏎ New line · ⌘⌫ Clear · ⎋ Back`, plus `⌃⌥S Scope` for recurring events
and `⌘Z Undo last save` while an undo record exists. Buttons mirror the key
actions.

## Highlights and live preview

Only matching `input.text` responses are painted. Route, root hue, clock, buffer,
reason sign, reason, and prose use Bob's validated ranges; unknown span kinds stay
neutral, invalid UTF-8 boundaries never crash or mis-highlight, and repainting never
moves the caret, breaks composition, or registers text undo. Range errors add red
underlines with Bob's messages and suggestions.

The live preview shows Bob's `preview.row` and bullets verbatim, dimmed and labeled
while validation is pending or fails — a stale preview never authorizes a write. A
null row (for example an invitation awaiting reply) gets an explicit waiting
explanation, never a fabricated task. Saving sends the current text and lets Bob
validate again.

## Time rail

The editor's rail reuses the agenda's hatched-wing primitives with a larger solid
meeting capsule and proportionate wings, drawn only from Bob's reported times. Before
and after reason labels come from the structured effective fields; the rail also
shows the occupied/meeting sentence, the root hue, and a midnight-clipping label
when the buffered span runs past midnight. Missing reason fields on an older
supporting Bob omit the label. Decorative geometry is hidden from VoiceOver, which
gets a summary of both spans and reasons.

## Saved versus applied, clear, undo

`ok: true` with `saved`, `cleared`, or `unchanged` is success. `sync_failed` still
means saved: the banner shows Bob's warning and recovery detail, with no second
sync from the Mac. After a mutation the mode returns to the picker with a status
banner, reloads the list so note chips reflect Bob, and refreshes the agenda store
through its normal entry point.

- **Clear** appends a deliberate clear for the selected scope (explicit `-c`, never a
  guessed empty write).
- **Undo** (Command-Z) re-saves the prior canonical text, or clears the scope the
  first save created. Failed or unchanged operations never replace the record; undo
  is consumed after success and never adds its own undo entry. No persistent undo
  journal.

On transport failure the draft is retained and the result marked uncertain; retry
reloads before writing, never blind-writes. Read-only, empty-list, no-match, and
unsupported states stay distinct, with bounded retry for recoverable failures.

## Compatibility

Event notes need a `bob` that provides `gcal note -f json` (schema 1): list, show,
preview, save, and clear. Unknown display strings degrade neutrally; a schema
mismatch refuses with Bob's error, never a silent fallback. See
[Protocol](protocol.md) for the command and the compatibility table.

Grammar, precedence, and the JSON contract live in Bob's
[Private event notes](https://bobs-org.github.io/gcal-notes/) and the
[Plan an event you don't own](https://bobs-org.github.io/guides/plan-events-you-dont-own/)
guide.

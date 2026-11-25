---
title: "Mac Capture meeting notes"
description: "File clipboard meeting notes from Capture: preview, choose, file, and open the result."
---

Meeting Notes mode files clipboard meeting notes through `bob ref meet`.
Bob owns matching, parents, and vault writes; the app renders Bob's JSON
and orchestrates the process ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)).

## Entry routes

- **Command-M** from any capture draft, empty or not. Routes before AppKit
  minimize handling; a repeat press is consumed.
- **File Meeting Notes…** in the menu-bar status menu.
- **Notes** on an agenda Calendar row. Started rows with an event token and
  `meeting_notes.state: missing` carry a focusable trailing **Notes** action
  beside Event Note; Command-M while focused files that event. Future,
  cancelled, filed, unknown-state, and ID-less rows offer no action. Missing
  fields from an older bob add no action.

Command-M works with a nonempty draft. The capture draft stays mounted and
retained underneath; exit restores its first responder. Event Note mode and
Meeting Notes mode are mutually exclusive. When `ref meet` is unsupported,
the menu item hides and the sheet reports the update message.

## Preview

The sheet shows the meeting title, date and span, destination, effective
status, auto-match evidence, warnings, TL;DR, next steps, section counts,
and transcript disposition from Bob's preview. **Change meeting** lists
recent meetings with filed rows marked. A Next/Read control passes an
explicit override; otherwise Bob's configuration wins.

Return files only the current `would_file` preview with its exact event
identity and `notes.sha256`. Return on a candidate selects and previews it;
it never files. Repeat Return starts one write. Option, status, parent, or
overwrite changes invalidate the preview and fetch a fresh one.

## Choices and receipts

- `ambiguous_meeting` / `no_meeting` offer Bob's candidates or the recent
  list; rows without a token cannot be selected.
- `needs_parent` offers Bob's parent candidates.
- `already_filed` offers Open existing and an explicit Replace choice; only
  that choice permits overwrite, followed by a new preview and Return.
- `notes_changed` clears approval and re-previews with a notice; it never
  files automatically. `no_notes` / `notes_unreadable` show a calm retry state.
- Filed and queued are separate terminal receipts. Filed offers Open note via
  existing Obsidian navigation. Queued stays visibly queued with its next step
  (`bob ref scan`) and never offers an Open action for an uncreated path.

## Keys

| Key | Action |
| --- | --- |
| Command-M | Open Meeting Notes (agenda focus selects the event) |
| Return | File the current preview, or select and preview the candidate |
| Up / Down, Control-P / Control-N | Move the meeting or choice selection |
| Escape, q (outside text controls), Control-[ | One level back, then close; q types in filters, Control-[ never types |
| Repeat Return / repeat Escape | Consumed; one write at a time |

Leaving discards session state and cancels reads; a write in flight settles
and its receipt stays observable with one refresh notification.

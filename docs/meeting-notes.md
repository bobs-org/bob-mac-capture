---
title: "Mac Capture meeting notes"
description: "File clipboard meeting notes from Capture: preview, choose, file, and open the result."
---

Meeting Notes mode files clipboard meeting notes through `bob ref meet`.
Bob owns matching, parents, and vault writes; the app renders Bob's JSON
and orchestrates the process ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)).
Argv, schema, and capability caching live in [Mac Capture protocol](protocol.md#meeting-notes).

## Entry routes

- **Command-M** from any capture draft, empty or not. Routes before AppKit
  minimize handling; a repeat press is consumed. When Bob is known not to
  support `ref meet`, Command-M is consumed so it cannot minimize Capture.
- **File Meeting Notes…** in the menu-bar status menu.
- **Notes** on an agenda Calendar row. Started and ended rows with an event
  token and `meeting_notes.state: missing` carry a focusable trailing **Notes**
  action beside Event Note, including x/DONE. Command-M while focused files
  that event. Future, cancelled (`-`), filed, unknown-state, absent-state, and
  ID-less rows offer no action. Missing fields from an older bob add no action.

Command-M works with a nonempty draft. The capture draft stays mounted and
retained underneath; exit restores its first responder. Event Note mode and
Meeting Notes mode are mutually exclusive. The first unsupported attempt shows
the update message and leaves ordinary Capture usable. After that, the menu
item, agenda Notes action, and Command-M stay hidden or consumed until Recheck
Bob or a new executable identity probes again.

## Preview

The sheet shows the meeting title, date and span, destination, effective
status, auto-match evidence, warnings, TL;DR, next steps, section counts,
and transcript disposition (`notes.transcript`) from Bob's preview. Receipts
also show `commit_warning` when Bob returns one. **Change meeting** opens the
recent-meeting chooser, keeping the current list visible while a fresh list
loads; Escape restores the previous preview without filing. Filed chooser rows
are marked. A Next/Read control passes an explicit override; otherwise Bob's
configuration wins.

Return files only the current `would_file` preview with its exact event
identity and `notes.sha256`. Return on a candidate, parent, or replace action
selects it; it never files. Repeat Return starts one write. Option, status,
parent, or overwrite changes invalidate the preview and fetch a fresh one.

## Choices and receipts

- `ambiguous_meeting` / `no_meeting` offer Bob's candidates or the recent
  list; rows without a token cannot be selected or clicked.
- `needs_parent` offers Bob's parent candidates; arrows and Return choose one.
- `already_filed` offers **Open existing**, **Review replacement preview**, and
  **Keep existing**. Only explicit replacement permits overwrite, followed by a
  new preview and Return.
- `notes_changed` clears approval and re-previews with a notice; it never
  files automatically. `no_notes` / `notes_unreadable` show a calm retry state.
- Filed and queued are separate terminal receipts. Filed offers Open note via
  existing Obsidian navigation. Queued stays visibly queued with its next step
  (`bob ref scan`) and never offers an Open action for an uncreated path.

## Keys

| Key | Action |
| --- | --- |
| Command-M | Open Meeting Notes (agenda focus selects the event) |
| Return | File the current preview, or activate the highlighted choice |
| Up / Down, Control-P / Control-N | Move the meeting, parent, or replace selection |
| Escape, q (outside text controls), Control-[ | One level back, then close; q types in filters, Control-[ never types |
| Repeat Return / repeat Escape | Consumed; one write at a time |

Leaving discards session state and cancels reads. A write in flight keeps the
sheet visible until it settles; Back, Escape aliases, hide, panel switch, menu
entry, and Event Note cannot replace that write. One filed or queued receipt
refreshes the agenda and Refs library.

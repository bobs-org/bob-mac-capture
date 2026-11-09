---
title: "Mac Capture typing tips"
description: "One-line Next time tips when a capture sigil was typed with Shift, fading as the unshifted alias becomes habit."
---

When a key without Shift would have typed the same capture sigil at the caret, Bob Mac
Capture shows one quiet "Next time" line on the first frame of the list or picker that
sigil opens. Bob proves every tip. The app never keeps an alias table, never rewrites
the draft from a tip, and never delays completion, preview, Similar Tasks, or Return.

## Where and when

The row sits at the foot of the completion-list card, under a hairline, pinned so it
does not scroll away. It appears only in that list's first frame. Filtering the query
leaves it in place. Closing the list, accepting a row, submitting, or hiding the panel
clears it. A tip that arrives after the list is already open is dropped.

This page covers the `@` and `#` lessons that open a completion list. Picker lessons
(`^`, `:`, `+`, `~`, `&`, `*`) use the same row at the foot of the picker card once that
host ships.

## Lessons

| Lesson | Unshifted key | Sigil | Phrase | Surface |
| --- | --- | --- | --- | --- |
| `route_after_text` | `.` | `@` | after a word | Completion list |
| `hash_menu` | `/` (then `\`) | `#` | after a word, or right after a route | Completion list |
| `block_id_after_route` | `.` | `^` | right after a route | Picker (coming) |
| `link_after_route` | `;` | `:` | right after a route | Picker (coming) |
| `task_link_item` | `;` | `:` | at an item start | Picker (coming) |
| `move_bullet_caret` | `.` | `^` | on a move bullet | Picker (coming) |
| `move_bullet_colon` | `;` | `:` | on a move bullet | Picker (coming) |
| `parent_task` | `,` | `+` | right after a route, or after a word | Picker (coming) |
| `relation` | `=` | `~` | after a word | Picker (coming) |
| `dependency` | `.` | `&` | once routed | Picker (coming) |
| `blocked_task` | `;` | `*` | after a word | Picker (coming) |

A physical Shift or Option press of `@` or `#` is what asks Bob. Paste, Undo, Redo,
repeats, marked text, and the app's own alias output never ask.

## Fading

Each physically typed sigil that Bob would have aliased is a miss. Each surviving
forward alias (`. ` → `@`, `/` → `#`, and the rest) is a hit. Hits count even with tips
off. Escaping an alias — Undo of the rewrite, a fast second `.`, Space or Escape on the
empty route list, or a second `/` or `\` that puts the literal back — withdraws that
hit and silences the lesson for the rest of the panel session.

At most one tip shows per panel session. After three learning tips, further tips wait
for a growing gap of misses (2, then 4, then 8). Four recent chances at a 75% hit rate
enter fluency and hide the tip; dropping below 50% leaves fluency and the tip can
return.

## Settings

Settings → Typing Tips:

- **Show typing tips** (default on). Off records no intents, spawns no tip requests, and
  shows no tips.
- **Reset typing tips** clears the ledger so every lesson starts fresh.

## Ledger

The ledger is a JSON string in the app's defaults, with no draft text:

```sh
defaults read org.bobs.bob-mac-capture org.bobs.bob-mac-capture.typing-tips
```

It stores per-lesson recent hits and misses, how many tips have been shown, and weekly
counts. A corrupt or unknown-version blob resets to empty.

## Compatibility

| bob | Mac | Behavior |
| --- | --- | --- |
| new | new | Tips are shown. |
| new | old | The old Mac ignores the new fields. |
| old | new | The `sigil_alias_tip` key is absent, so the Mac stops asking that bob and shows no tips. |
| old | old | Unchanged. |

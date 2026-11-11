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
does not scroll away. Picker tips use the same row at the foot of the picker card,
under a divider and below its detail strip. A tip appears only in the first frame of the
list or picker anchored at the sigil, even if you keep typing its query before that
surface opens. A list or picker left from the previous token does not count. The first
anchored surface consumes the opportunity; the tip never jumps between surfaces.
Filtering leaves the row in place. Editing at or before the sigil, or pausing first on a
draft with no anchored surface, drops the tip. Closing the surface, accepting a row,
submitting, or hiding the panel clears a shown row. A tip that arrives after its
anchored surface is already open is dropped.

The picker includes the row only when its full height at the open row budget fits the
panel's screen space. A cramped panel drops the tip before it trims the candidate rows.

The trigger set is `@`, `#`, `%`, `^`, `:`, `+`, `~`, `&`, and `*`. Each lesson is shown only
on the surface Bob's rewrite opens for that sigil.

## Lessons

| Lesson | Unshifted key | Sigil | Phrase | Surface |
| --- | --- | --- | --- | --- |
| `route_after_text` | `.` | `@` | after a word | Completion list |
| `hash_menu` | `/` | `#` | after a word, right after a route, or in a notebook section bullet | Completion list |
| `directive_menu` | `\` | `%` | after a word | Completion list |
| `block_id_after_route` | `.` | `^` | right after a route | Picker |
| `link_after_route` | `;` | `:` | right after a route | Picker |
| `task_link_item` | `;` | `:` | at an item start | Picker |
| `move_bullet_caret` | `.` | `^` | on a move bullet | Picker |
| `move_bullet_colon` | `;` | `:` | on a move bullet | Picker |
| `parent_task` | `,` | `+` | right after a route, or after a word | Picker |
| `relation` | `=` | `~` | after a word | Picker |
| `dependency` | `.` | `&` | once routed | Picker |
| `blocked_task` | `;` | `*` | after a word | Picker |

A physical Shift or Option press of one of the trigger sigils is what asks Bob. Paste,
Undo, Redo, repeats, marked text, and the app's own alias output never ask.

## Fading

Each physically typed sigil that Bob would have aliased is a miss. Each surviving
forward alias (`. ` → `@`, `/` → `#`, `\` → `%`, and the rest) is a hit. Hits count even with tips
off. Escaping an alias — Undo of the rewrite, a fast second alias key (`.`, `;`, or
`=`), Space or Escape on the empty surface it opened, or a second same-key `/` or `\`
that puts the literal back — withdraws that hit and silences the lesson for the rest of the panel
session.

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
counts. The additive `dropped` map counts why bob-proved tips were not shown, using the
stable reasons `late_reply`, `sigil_edited`, `unanchored`, `superseded`, `closed`,
`not_due`, `session`, `host`, and `budget`. It stores no draft text. Older version-1
blobs without `dropped` load with an empty map. Reset clears the map with the rest of
the ledger; a corrupt or unknown-version blob resets to empty.

## Compatibility

| bob | Mac | Behavior |
| --- | --- | --- |
| new | new | Tips are shown. |
| new | old | The old Mac applies `\` → `%` through its generic rewrite path, ignores the new lesson id, and skips the double-tap arm. |
| old | new | The `sigil_alias_tip` key is absent, so the Mac shows no tips. An old Bob's `\` → `#` reply still arms the same-key double-tap. |
| old | old | Unchanged. |

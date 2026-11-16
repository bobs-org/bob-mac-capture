---
title: "Go To Notes in Mac Capture"
description: "Browse and open notes from Bob Mac Capture without capturing a draft."
---

## Open the Notes picker

Type `/` to open Go To · Tasks, then type a second `/` while its filter is
empty. Typing `\` then `/` reaches the same picker. Paste `//query` as the whole
draft to open Notes with a search already applied. A slash in a nonempty Tasks
filter stays in the search; repeats, IME-marked input, and a third slash in an
empty Notes filter are consumed. Older Bob builds that do not advertise the
continuation show **Update bob to search notes**.

## Browse and open a note

The Notes scope (`note_goto`) shows Bob's read-only vault catalog. Its empty
filter groups Today, Inbox, Areas, Projects, Notebooks, and Albums; type a query
to search Bob's title, alias, and path keys. Obsidian Base (`.base`) rows stay
available as View rows and open through the same read-only Obsidian route.

Return, Tab, click, Command-Return, and Control-Return open a note through
`obsidian://bob-open-notes` without line or caret movement. The panel hides and
discards the draft after dispatch succeeds; a failure keeps the picker open.
No `capture` request is made. Backspace on an empty Notes filter peels Bob's
`trigger_removal_range` back to `/`; Backspace on the empty Tasks filter then
removes `/`. Escape clears a search first, then leaves a `//` reopen chip.
Command-X, Shift-Return, and Option-Return are consumed. Control-C discards the
navigation draft without stashing it.

The card stays mounted across the swap: the scope capsule morphs, rows
cross-fade in about 120 ms with an ease-out curve (instant under Reduce
Motion), and the panel height never changes. Continuation renders the warm
in-memory Notes snapshot immediately while the real `//` fetch revalidates
and replaces only on change, keeping the live row; the peel back restores
the retained Tasks rows the same way. The snapshot fills from a background
`//` fetch on the first `/` session, on panel show (stale-while-revalidate),
and on debounced visible-note vault events; it is never persisted or logged.
Until rows exist, a quiet "Loading notes…" placeholder shows — never a
spinner. A failed fetch shows "Couldn't load notes", distinct from an empty
search. Scope changes announce ("Go To Notes, 184 notes"), and filter result
counts announce as usual.

## Recent notes

The empty Notes view shows up to eight recently opened notes in a Recent
section after Today. Recent is app-local history, never written to the vault,
and a search filters it away until the filter clears. Clear it in Settings
under Go To Notes.

---
title: "Bob Refs inspector"
description: "Bob Refs inspector column: lazy hydration, thumbnails, highlights paging, honesty rules, and the actions menu."
---

The inspector sits beside the Refs list at 760 pt and above. List layout, keys, and cards are in [Bob Refs](refs.md). Preview page size is Settings › References › Preview highlights per page (1–20, default 5); see [Settings](settings.md#references).

## Inspector

The inspector fills instantly from the list item, then upgrades
lazily: after the selection settles for 120 ms it loads the PDF's
intrinsics and `bob ref show <note path> -f json` concurrently,
canceling the previous load on every move. `ref show` results keep an
LRU of 32 keyed by note path and snapshot time; intrinsics cache by
file path, size, and mtime in memory (64) and under
`~/Library/Caches/org.bobs.bob-mac-capture/refs/` (1,000 entries plus
one thumbnail PNG each). What each kind shows:

- Papers, articles, and docs show a page-1 thumbnail (fixed space
  is reserved while it loads, so nothing jumps) and the outline:
  150 × 194 pt beside the facts in the wide layout, 112 × 145 pt
  above them in compact. Both draw from the one 300 × 388 px image
  the loader caches. Papers also show the Abstract excerpt; articles
  and docs show no excerpt. The wide layout sets the title in
  semibold title2 (3 lines) and the summary and quotes in body
  (quotes carry 3 pt of line spacing and clip at 6 lines); compact
  keeps semibold title3 (4 lines), callout quotes at 4 lines, and
  today's spacing.
- Chats keep the kind tile and lead with the outline plus the
  Bottom-line excerpt: the first paragraph (or up to 3 bullets) under
  Bottom line, TL;DR, Summary, Executive summary, or Key findings.
- Every hydrated row adds reading time to Pages
  ("22 · ≈ 70 min · 3 Pomodoros", 230 words per minute, Pomodoros of
  25 minutes), Tasks ("2 open") from `ref show`, the top-level
  outline headings (up to 6), and your annotations in one HIGHLIGHTS
  section in note order: ordinary highlights, image highlights, and
  standalone notes. A highlight that carries your comment, an attached
  image, or an unresolved image shows a pale-yellow note card marked
  with the sticky-note glyph; the header's note chip counts those
  cards, and the disclosure row says how many hidden entries carry
  notes and, when hidden entries hold resolvable images, how many
  images (`+12 more · 3 with notes · 2 images · ⌃D shows 5 more`).
  Image highlights render in the quote slot (the 2 pt yellow rule on
  the left) fitted to the column, never upscaled, with a reserved
  frame from the file's header so Ctrl-D's follow-tail never jumps.
  Attached images sit inside the note card, 8 pt apart, fitted to the
  card's inner width. A missing, unreadable, or unresolved image is a
  one-line "Image unavailable" row with the file's base name, never a
  box. If a header succeeds and the bitmap later fails, the reserved
  frame stays and the unavailable caption sits inside it. Standalone
  notes join the feed as note cards with no quote.
  Same-page entries share one page label. Quotes render balanced
  `**bold**` runs as strong emphasis, and a hover tooltip on a
  highlight shows its full text. The preview shows the first page (5
  by default, Settings › References › Preview highlights per page);
  the disclosure row (`+N more · ⌃D shows …`) or Ctrl-D while that
  row is visible reveals the next page of highlights until all show.
  Revealed pages reset on every selection change and on every show.
  Page labels show as bob writes them (`Page 1` stays `Page 1`).
- Chats name consolidated reports and researcher drafts in the
  byline from the stem (`__final`, `__x`).
- The Reading task fact names where the reference's task lives: the
  `book` symbol, the real parent route, and the lane label
  (`sase · Next`), or `Archived · done/sase_done` once archived.
  Parent captions use the real route; only frozen v1 rows keep the
  legacy `_ref`-stripping (`obsidian_ref` reads as `obsidian`).

Honesty rules: absence stays absence (facts omit their row); a
publication date is not a file date; a highlight count is not
progress; git dates carry "≈"; reading time is an estimate. A locked
PDF reads "Preview unavailable: encrypted"; any other PDF failure
reads "Preview unavailable". When `ref show` fails the basic
inspector stays and adds a dim "Notes unavailable". Page counts and
outline headings feed back into the ranking signals, so rows gain
`N pp` and search can match headings.

The ⌘K actions menu pops up below the selected row (at the list's
center when the row frame is unknown): Open in Highlights (↵), Close Tab
(⌃X, matched Tabs rows), Open
Note (⌘↵), Reveal in Finder (⌥↵), Copy… (⌘Y), Rename… (⌘⇧R),
Link to Today… (⌘N), Mark as Seen or Mark as New (⌥N, Ready and Next
rows), Open
Source URL (only with `urls`), Open Narration (only with `audio`, in
the default app), Open in Default App, Refresh Library (⌘R), and Scan
for New References (⌘S, last; disabled while a scan runs). Copy…,
Rename…, and Link to Today… open their matching cards. ⌥N flips NEW
in place; ineligible rows beep. A seen row stays in NEW until the next
unfrozen ranking.

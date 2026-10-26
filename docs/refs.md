---
title: "Bob Refs"
description: "Bob Refs library panel: snapshot, Today, scan, sorting, NEW, ranking, cards, opening, and Tabs."
---

Bob Refs is a thin client of `bob`: it filters, ranks, sections, and presents what `bob` returns, never parses frontmatter or note bodies, and never writes the vault itself. Keyboard rows also appear in [Keyboard](keyboard.md). The inspector column is in [Bob Refs inspector](refs-inspector.md). Ranking invocation is in [Diagnostics](diagnostics.md#refs-rank). Disk, memory, and Accessibility rules are in [Permissions](permissions.md). Scan, load, and tab-close recovery are in [Recover Bob Refs](https://bobs-org.github.io/guides/recover-bob-refs/).

## Bob Refs

[![Bob Refs browse panel with reading-state sections and the selected reference's inspector](images/refs-browse.png#only-light)](images/refs-browse.png)
[![Bob Refs browse panel with reading-state sections and the selected reference's inspector](images/refs-browse-dark.png#only-dark)](images/refs-browse-dark.png)

Synthetic CI render. Open the image for full-size text.

Bob Refs is a quick-open panel for the reference library: one keystroke shows
every PDF-backed reference note, with kind and reading state on every row.
Return opens the original PDF in Highlights and changes nothing in the vault —
opening never mutates reading state, task lanes, or review state.
Bob Refs ⌘S runs `bob ref scan -a -w` and presents its JSON report.
When enabled, Bob Mac Capture passively observes ⌘S in Highlights and scans
after the library PDF save settles. The 15-minute cron runs without `-a`.
An older `bob` that rejects `-a` is retried without it and remembered
for that executable.

### Data

- Snapshot: `bob ref list -R all -A -f json` (schema version 1), plus `-g`
  when some row still lacks an `added` date, or has a git date but no git
  instant yet. Every optional field decodes
  with `decodeIfPresent`, so an older `bob` still works: no `blocked`
  reads as not blocked, a row without `task` joins Today on the note
  path, and unknown fields are ignored. Any other schema version is
  rejected like any other refresh failure.
  `added_at` is the most precise instant `bob` knows on the row's `added`
  day (RFC 3339, for example `2026-10-17T09:12:44-04:00`) and is `null`
  when `bob` knows only the day. It parses once into `RefItem.addedAt`
  when the catalog is built; an older `bob` decodes it as nil, and a
  malformed value becomes nil without failing the row.
  Each row's `task` object (`path`, `block_id`, `link`, `mark`,
  `archived`; `block_id` `ref` on frozen v1 trackers) names the
  reference's single ordinary reading task: where it lives is the
  reference's parent, and a `done/` path reads as archived.
- Today: `bob plan -f json` (schema version 2). Today entries join on
  `(task.path, task.block_id)`, so two references whose tasks share one
  parent note no longer both light up when only one is linked; rows
  without a task fall back to the note-path join.
- Scan: `bob ref scan -a -w -f json` (schema version 1) names every created
  and updated note, the intake moves, held PDFs, and per-PDF failures or a
  coded hard failure. Additive fields (`generated_at`, `summary.held`,
  `held[]`, `notes[].marker_write`) decode as empty on an older `bob`. The
  app decodes every field except `schema_version` loosely, ignores unknown
  fields, and rejects any other schema version like any other scan
  failure. After a writing scan, `bob` rewrites
  `<state>/bob-cli/ref/last-scan.json` (`XDG_STATE_HOME`, else
  `~/.local/state`) and, on macOS, posts the Darwin notification
  `org.bobs.bob.ref.scan-finished`. Bob Refs observes that ping, reads the
  receipt off the main thread (bounded at 4 MB), and ignores a duplicate
  content hash. Launch never reads a receipt.
- The snapshot (with git-added dates and instants) and the last Today
  value persist
  in `refs-snapshot.json` under `~/Library/Application Support/`
  `org.bobs.bob-mac-capture/`, so a cold launch paints immediately.
  `git_added_at` maps each git-dated note path to its birth commit's
  RFC 3339 instant; older caches decode it as empty and the `-g` pass
  refills it once. Open history
  (note paths and timestamps only) lives in `refs-open-log.json`
  beside it; NEW marks (`new`/`seen` plus the instant) in
  `refs-new-marks.json`. All three files are mode 0600
  in a 0700 directory.
- `RefsCore` (the `Sources/RefsCore` target, Foundation plus CaptureCore
  only) owns the decoding, the `RefItem`/`RefKind`/`RefState`/`RefScope`
  model, the ranking, captions, and inspector extraction, the
  `BobRefsFetcher` over `BobProcessClient`, and the stores.

### Updates

Bob Refs remembers its query, kind scope, Newest and Tabs filters, selected
reference, revealed highlight pages, and list and preview positions in memory
for the app's lifetime. Every ordinary show restores that view using fresh
library or Tabs data, except when a reference was added since the panel was
last shown and its `added` day is within the 3-day NEW window (renames and
moves of older notes do not count): that show resets to the fresh-launch
defaults and selects the new reference (the newest batch, then the first
listed id in that batch). An arrival that lands in the first 10 seconds of
an untouched ordinary show — typically the show's own pull — also resets
and selects it. A Ctrl+Tab switch never resets for an arrival: the new
reference joins the listing without moving the selection. The Highlights Tabs
key (Command-T) opens from fresh defaults with Tabs on and the focused PDF
selected. Nothing done in that session is remembered: the next ordinary show,
including Ctrl+Tab back, returns to the view from before it. It still defers
a new-reference reset to the next ordinary show.
Selecting the reference first cancels the reset. Ctrl-C resets it to the
fresh-launch defaults; quitting or restarting starts fresh.

Visible inspectors rehydrate notes, highlights, thumbnail, and outline after
a library refresh, keeping selection, scroll position, and revealed page while
old content stays until the new load completes.

`RefsLibrary` owns the refresh service: the snapshot, the `-g`
backfill on its own lane, Today, a one-shot Spotlight sweep for
last-used dates and page counts, and missing-PDF checks. It paints from
cache at launch and watches the vault root (root `*.md` notes) plus
`<vault>/ref`, `<vault>/lib`, and `<vault>/done`
(0.5 s debounce). Dot-path-only batches (`.git/`, `.obsidian/`, `.trash/`) no
longer trigger a refresh; any visible path, including a `lib/` PDF, still
does. Today refreshes every 10 minutes, after sleep, after
every capture, and in the background on panel open unless a panel-open
Today refresh ran in the previous five seconds; a stale
snapshot is re-read on every panel open. The `-g` lane runs only while
some row lacks an `added` date (or a git-dated row lacks its
instant) and only after the snapshot
publishes, so the first paint never waits; it merges
git-sourced dates into dateless rows, and a `-g` failure keeps the
published list, only logged. One refresh per lane runs at a time;
a trigger during a refresh schedules exactly one follow-up. A failed
refresh keeps the last good list and records `.failed`, which the
footer reads as "Update failed · ⌘R to retry". Only Highlights and
default-app opens append to the open log. `RefsPanelModel` holds the
query, scope, frozen listing, and id-based selection: typed text reaches
the model on every keystroke, late library data refreshes row content
in place; arrivals that land while the panel is open join the visible
list on their own when the Tabs filter is off, no rename, Today-link,
or copy card is open or in flight, there is no pending open, and the
selected id is nil or still available (otherwise they join at the next
re-rank, with a "1 new reference" / "N new references" VoiceOver
announcement when they join; ⌘R re-ranks from the new data once the
refresh completes, keeping the selection when it still exists), an
open error re-shows the panel with the query, selection,
and pending open intact, and Return on a vanished row shows "No longer
in your library" instead of opening whatever slid into its index. A `refs-pull`
lane runs `bob vault-sync -q` on every Refs panel show (throttled to one
pull per 5 s) and before every ⌘R refresh (single-flight, unthrottled);
a trigger that arrives while a pull is running joins that pull, no pull
runs during a scan or rename, and a pull failure is only logged — it never
touches `refreshState`, banners, or the footer. The pull itself never
refreshes; the existing vault watcher sees the fast-forward and runs the
normal snapshot refresh. An ⌘S scan runs on `refs-scan` (300 s timeout)
without cancelling other lanes. Watcher changes defer one refresh until
it completes; a save during a scan or rename queues one follow-up. After
`bob` exits, each completion refreshes the snapshot and Today, even on
failure, before publishing the scan notice, so moved intake files appear
before re-ranking.

### Scan after saving in Highlights

With **Scan after ⌘S in Highlights** enabled, Bob Mac Capture passively
observes plain Command-S while Highlights (or the override app) is frontmost;
the key still reaches Highlights unchanged. Only `lib/`/`xlib/` documents
scan: an unknown path permits the full scan, an outside path disarms it. The
trigger waits for quiet library events for 1 second, falls back after 2.5
seconds without events, and caps at 10 seconds.

The scan runs `bob ref scan -a -w -f json`. With
`highlights.coordinate_pdf_writes: true`, bob's coordinated `.forMerging`
write saves first, applies the marker to fresh bytes, and reloads the same tab.
With coordination off, Highlights may show “changed by another application”;
choose **Save Anyway** to keep annotations. About 350 PDFs take 8 seconds.
No save-only notification is added; scan and open-PDF receipt rules stay.

### Sorting

An empty query shows browse sections in order — Just scanned (this scan's
created references, in `bob`'s order, uncapped, while the scan mark is at
most 15 minutes old), NEW (Ready/Next rows that are marked new, or unmarked
unopened arrivals within 3 local days, newest first by new-since,
uncapped), Now (references whose reading task has a Task Link under today's open
Pomodoros, in ledger order),
Reading, Next (blocked rows last), Ready by added desc (blocked rows
last), Recently opened (read/dropped/unknown opened within 14 days,
capped at 5), then the Library by last activity. The Now section header
reads `NOW`, distinct from Newest's `TODAY` date group. NEW is Mac-local
presentation state: it never runs `bob`, never writes the vault, and is
not the review walk's NEW freshness tier. A marked row's new-since is
the mark instant; an arrived row uses `addedAt` when known, else the
start of its `added` day. Day counts use the
panel calendar, so NEW, Recently opened, recency, and Library
activity never shift by a day in US evenings. Each item appears in the
first section that admits it; over-cap rows fall through; empty sections
are omitted; the final tie-break everywhere is the note path. Tabs mode
orders the current tab first, then recent tabs, with tab-bar order as the
tie-break and unmatched tabs last. A typed
query collapses the sections into one ranked list with tiers that never
cross: T0 exact (title/stem equality or a pasted arXiv id, DOI, or URL),
T1 title/stem word prefix (any length; a 2-character prefix counts),
T2 fuzzy (`q >= 0.55`; two characters need a contiguous non-word
substring, one character needs a word prefix), T3 author/area/kind/outline
heading. Within a tier, `score = m + P + W + L + F + R`: mean token
quality, prefix bonus 0.15, whole-word bonus 0.10, lane prior (Now
0.20, reading 0.15, next 0.12, ready 0.08, blocked −0.02, dropped −0.20,
read/unknown 0), frecency weight 0.25 (half-life
`frecencyHalfLifeDays`), and added-date recency weight 0.10; ties break
on shorter title, newer added, then path. The dropped prior is −0.20 rather than the planned −0.10: at −0.10 a
dropped title-prefix match (prefix bonus +0.15) outscored a Ready
non-prefix word match, failing the "sinks the dropped row" golden.

**Newest** (`RefsListOrder.newest`) lists every reference of the scope in
a date-grouped timeline instead of the sections above, with the same
tiered search when a query is typed. ⌘0 changes order, never membership:
the rows are exactly the ones the scope (and, with a query, the T0–T3
search) shows in the ranked order. Rows sort by `added` day, newest first;
then by `added_at` instant, newest first, with timed rows ahead of
untimed rows on the same day; then by note path. Rows without an `added`
date come last, in path order. Consecutive rows form date groups in the
panel calendar (`signals.now`, `signals.calendar`), so groups never shift
a day in US evenings:

| Group               | Rule                                  | Header          | Trailing detail |
| ------------------- | ------------------------------------- | --------------- | --------------- |
| Today               | day ≥ today (future dates clamp here) | `TODAY`         | `Oct 18`        |
| Yesterday           | 1 day ago                             | `YESTERDAY`     | `Oct 17`        |
| Weekday             | 2–6 days ago                          | `THURSDAY`      | `Oct 16`        |
| Month               | older, same year as today             | `OCTOBER`       | —               |
| Month, earlier year | older, earlier year                   | `DECEMBER 2025` | —               |
| Undated             | no `added`                            | `UNDATED`       | —               |

The weekday window matches the caption rule for 2–6 days ago, so a
weekday group and the month group can share a month. Each group is a
`RefsSectionKind.added(RefsAddedGroup)` with a stable id (`day-2026-10-16`,
`month-2026-09`, `undated`), its title and trailing detail, and an
accessibility label ("Added today, October 18", "Added in December 2025").
Row captions keep their shape; only the date phrase changes: `added 9:41 AM`
inside a day group (nothing for an untimed row, because the header names
the day), `added Oct 7` inside a month group, nothing when undated, and
the `≈` mark stays on git-sourced dates (`added ≈ 3:12 PM`). Times use
the panel calendar's time zone and locale. The why-here line is the exact
capture date (`Added Oct 16 at 9:41 AM`, `Added ≈ Sep 27 at 3:12 PM · from
vault history`, or `Undated · bob has no added date for this note`);
Newest search keeps the match reason. Section jumps move between date
groups in Newest, searched or not.

### NEW

A row is NEW when it is Ready or Next (blocked included) and either a
⌥N `new` mark still holds — no open-log event or Spotlight last-used
date after the mark — or it has no mark, its `added` day is within 3
local days, and it has never been opened or annotated. A `seen` mark
hides NEW. Ways out: open the PDF, ⌥N, the reading task leaving
Ready/Next, aging past the window (unmarked rows only), or a successful
Link to Today from Bob Refs. Links made in Obsidian or Capture leave
the row NEW. NEW never runs `bob`, never writes the vault, and never
changes reading state, task lanes, Today, or review freshness; it is
not the review walk's NEW freshness tier. ⌥N stores the smallest mark
that produces the flipped state, so a second press restores the start
and an arrived row still ages out on schedule.

### Tuning

`swift run refs-rank [--plan plan.json] [--opens open-log.json]
[--new-marks refs-new-marks.json] [--scope chats]
[--now 2026-10-08T09:00:00] [--tz America/New_York]
[--newest] [query...] < ref-list.json` ranks a `bob ref list` snapshot with the
same ranker the panel uses, for tuning against live output on this Mac
or athena. `--now` accepts a full ISO 8601 time with an offset or a
local date-time without one, interpreted in `--tz` (default: the current
time zone); that calendar ranks the snapshot. Browse mode prints the
sections; search mode prints
`rank  tier  score (m P W L F R)  state  kind  title` with padded columns
(rank 4, tier 9, state 8, kind 7), each followed by its why-here line.
`--newest` prints the Newest timeline instead, in browse or search: one
`## TITLE (count)  detail` line per date group, then one row per line as
`added_at  state  kind  title`, where `added_at` is the instant in `--tz`
(the bare day when only the day is known, `undated` when neither), so
`bob ref list -R all -A -f json -g | swift run refs-rank --newest`
shows the timeline against live output.
`--new-marks refs-new-marks.json` loads Mac-local NEW marks into the
same ranker.
The target is never bundled: `Scripts/bundle.sh` copies only the
`BobMacCapture` product.

### The panel

`RefsPanelController` owns a borderless non-activating glass panel
(`RefsPanel`, a near-full-screen reading room: `min(1440, visible
width − 96)` by `min(1000, visible height − 72)`, centered on both
axes — 1344 × 798 pt on a 1440 × 870 pt MacBook; the Copy card covers
the list below 760 pt wide). The SwiftUI content sits in an
`NSGlassEffectView` (corner radius 20); the SwiftUI root itself
carries no glass modifier so the `ImageRenderer` design fixtures
stay reviewable. Under Reduce Transparency an opaque window
background paints beneath the content. It prewarms at launch
(already at the show size), recomputes its frame on every show,
fades in over 0.12 s as
content scales 0.98 to 1.0 (fade only under
Reduce Motion), hides at once with no fade-out, and hides when it
resigns key, like Spotlight. Highlights stays frontmost throughout:
the panel never calls `NSApp.activate`. The height is fixed while
the panel is visible; filtering never resizes it.

Layout, top to bottom: the 52 pt search bar (magnifier, 20 pt field,
Newest or Tabs token, scope token, "`N open · M`" or "`k of M`" count, refresh spinner),
the banner when one is up, the content well (list beside the
inspector on `.regularMaterial` at radius 12 with a hairline
stroke), and the 30 pt footer (key hints including "⌘S Scan", plus the library
status: "Scanning library…" with a spinner while a scan runs, "Update
failed · ⌘R to retry" when a refresh failed, the scan outcome — "Added
N references", "No new references", or "Scan failed · ⌘S to retry" —
optionally followed by open-PDF clauses such as "1 PDF refreshed in
Highlights" or "1 PDF waiting while you read", "Updating…", or
"Updated …"). The list column takes
`min(round(width × 0.52), 560)` of the panel width (560 pt at
reading-room widths, 458 pt at the compact 880 pt reference) and the
inspector shows at
760 pt and above. The inspector picks one of two layouts from the
panel width: wide when its column reaches 568 pt (24 pt padding, a
readable column of at most 720 pt centered in the inspector), compact
otherwise (today's 18 pt padding). Rows are 44 pt and two lines: the New dot (accent, only while the
row is NEW),
the kind tile, the rich title (semibold while NEW; code spans styled, accent matches) with its caption (a stem-only or secondary match
renders in accent, and a matched author the
caption already shows is not repeated), and the pink Now pill (the
Pomodoro name, or `NOW` when it is unnamed),
annotation and narration marks, and the state glyph. Section headers
are 26 pt and pinned (`NEW`, `NOW`, `READING`, …; Newest: `TODAY`,
`YESTERDAY`, …). The selected row stays fully visible
below the pinned header; a show keeps it when still listed, unless a
new reference resets the view, and a re-rank selecting the first row
returns the list to its
top. Moving up lands the selection under its section header. The NEW header leads with the same accent
dot; a selected NEW-section row trails "⌥N Mark Seen"
or "⌥N Mark New". Newest rows are date groups (`TODAY`,
`YESTERDAY`, a weekday, a month, `UNDATED`) with the count after the
title and a trailing day on day groups (`Oct 18`). The Newest token is
an accent capsule with the text "Newest" and an `xmark`; activating it
returns to library sections. VoiceOver reads each row as one element —
"Title, Paper, Ready, added today, 22 pages, Now in BLOG
Pomodoro, new" — with the kind said once and the selected
row carrying `.isSelected`. The inspector fills instantly from the
list item (hero, kind/state/New/Now chips, title, byline, an
Added/Finished/Pages/Opened/Notes/Reading task/Narration facts grid
with absent rows omitted, the why-here line, and the vault PDF path;
see [Bob Refs inspector](refs-inspector.md) for the hydrated column); a missing PDF shows an
orange "↵ opens the note instead" callout. States: 8
skeleton rows on first launch; a centered Retry
(⌘R) and Copy Diagnostic card when no cache exists and the refresh
failed; a centered "No references match" empty state
("Not in your library yet? ⌘S scans for new references", or "Scanning
for new references…" mid-scan); dimmed
unavailable rows that never open whatever slid into their index. A scan
finishing while the panel is visible re-ranks once like ⌘R, puts
Just scanned first with its first row selected, and
announces the outcome to VoiceOver; while hidden it posts a macOS notification instead ("Added N
references", or the failure), and clicking it shows Bob Refs with the
section on top. A writing scan that refreshed an open PDF — or that
could not because Highlights did not answer — notifies or updates
the footer as in [Open PDFs in Highlights](#open-pdfs-in-highlights).
Problem scans raise a banner: a Copy Diagnostic warning for
per-PDF failures, a Scan Again plus Copy Diagnostic error for
hard failures, and a Scan Again warning when Highlights needs
you.

| Key | Bob Refs panel |
| --- | -------------- |
| Return, Tab, double-click | Open in Highlights (the note when the PDF is missing) |
| Command-Return | Open the note in Obsidian |
| Control-Return | Open the reading task's file in Obsidian, landing on the task line; rows without a reading task beep |
| Option-Return | Reveal the PDF in Finder |
| Up/Down, Ctrl-P/Ctrl-N, Ctrl-K/Ctrl-J | Move (wraps) |
| Page Up/Page Down | Page the results list by one less than fits |
| Ctrl-X | Close the selected tab in Highlights (Tabs only); elsewhere passes through to search |
| Ctrl-D | Scroll the preview down by half its height; while the `+N more` row is on screen, Ctrl-D shows the next page of highlights at once; search keeps focus |
| Ctrl-U | Scroll the preview up by half its height; search keeps focus |
| Ctrl-C | Reset query, scope, filters, selection, revealed pages, and list and preview positions to fresh-launch defaults |
| Shift-Command-T | Reopen the most recently closed Highlights tab |
| Command-Up/Command-Down, Home/End | First, last |
| Option-Up/Option-Down | First row of the previous/next section (browse and Newest) |
| Command-0 | Toggle Newest: every reference by date added, newest first, grouped by day then month; typing still filters |
| Command-1 … Command-5 | Scope All, Chats, Papers, Articles, Docs |
| Command-R | Refresh library, Today, and git dates now; re-rank |
| Command-S | Scan for new references now (`bob ref scan -a -w` in the background; an older `bob` is retried without `-a`); a second ⌘S while one runs does nothing |
| Command-K | Actions menu for the selected row |
| Command-Y | Open the Copy card for the selected row |
| Command-N | Open the Link to Today card for the selected reference |
| Option-N | Mark the selected Ready or Next reference Seen, or New again; the row stays put until the next re-rank; other rows beep |
| Command-Shift-R | Open the Rename card for the selected row |
| Backspace on an empty query | Remove the Tabs or Newest token first, then the scope token |
| Esc, Ctrl-[ | Link to Today, Rename, or Copy card, then banner, then close while keeping the view |
| Shift-Tab | Consumed (no-op) |

While IME-composing, Return, Command-Y, Ctrl-D, Ctrl-U, Ctrl-C, Ctrl-X,
and Shift-Command-T pass through to the text system. Ctrl-C
always resets the view, even with defaults, and Ctrl-D and
Ctrl-U consume the key even when the preview is hidden, short, empty, or
at an edge. In Tabs, Ctrl-X closes the selected tab and Ctrl-D always
scrolls. With the `+N more` row fully visible
or at the preview bottom, Ctrl-D pages highlights at once
(clicking the row does the same);
elsewhere it scrolls half a viewport, and
with nothing hidden it is consumed and does nothing.
Shift-Command-T reopens the most recently closed tab, or does nothing.
Printable keys fall through to search. Result counts
announce 600 ms after typing stops, never on every keystroke.

### Open PDFs in Highlights

A writing scan that updates a PDF open in Highlights — `editor_saved_first`
is true, or the PDF's file name equals an open Highlights tab's
`fileName` — tells Bob Refs. The tab check uses the existing read-only
Highlights tab reader, only when a coordinated write did not already
save-first and Accessibility is already trusted. It never prompts.

| Event | Bob Refs visible | Bob Refs hidden |
| --- | --- | --- |
| Open PDF refreshed | Footer clause `1 PDF refreshed in Highlights` | Notification "Updated in Highlights" |
| `coordination_timeout` hold | Warning banner "Highlights needs you" with **Scan Again** | Notification "Highlights needs you", at most once per PDF until it stops being held |
| `editor_active` / `marker_changed` hold, or a refresh of a PDF that is not open | Footer clause `1 PDF waiting while you read` (holds only) | Nothing |

Open-PDF notifications are passive, silent, and grouped
(`threadIdentifier` `org.bobs.bob-mac-capture.refs-pdf-updates`) on the
existing `refs-scan` category ("Show in Bob Refs"). One refresh is titled
`Updated in Highlights`, with the display title as subtitle and a body
such as `Ready → Next · your unsaved highlights were saved first` (the
saved-first clause drops when Highlights did not save first; with no
status change the body is `Page-1 note updated`). Several refreshes are
titled `Updated 2 PDFs in Highlights` with the titles joined by ` · `.
A busy hold is titled `Highlights needs you`, with the display title as
subtitle and body `Highlights didn't answer — a dialog may be open. Bob will update this PDF once it's free.`
Clicking one opens Bob Refs and selects that reference when it is in
the catalog. Settings › References "Tell me when Bob updates an open
PDF" (on by default) suppresses notifications only; footer clauses stay.

### Copy card

Command-Y opens an in-panel card for the selected reference, or for the
focused Highlights PDF (see [Opening Bob Refs](#opening-bob-refs)). The fixed
keys copy `I` marker ID, `T` title, `W` wiki link, `U` source URL, `X` arXiv
ID, `D` DOI, `N` note path, `O` Obsidian link, `P` PDF path, `F` the PDF file,
`R` reading-task link, and `S` research reference. `C` opens a code picker
with a preview well (`Loading code…` while fetching). `M` copies the Markdown
(Option-M its `~` path). `L` opens a link picker on references bob rendered
from Markdown (`L` stays the Markdown link elsewhere; Option-U always copies
it). A `p. N in Highlights` chip marks the focused tab. Hidden C/L/M
keys explain why. Command-Y C Return copies the page's block; Command-Y L
Return copies the page's link.

`1`–`9` copy the visible commented highlights with page and block-link
provenance; `A` copies all commented highlights, standalone notes, and Bob's
notes, grouped under `### <Title>` (section description as a blockquote) when
`bob ref show` supplies sections, then `### Other highlights` and `### Notes`.
Empty sections and uncommented-only sections omit a group; older unsectioned
responses keep the previous A payload. `H` opens a highlight picker for every
highlight and standalone note (digits copy the window, arrows scroll, `A`
copies all) with non-selectable section titles that repeat when the window
starts mid-section. Return copies the selected row (marker ID
when available, otherwise wiki link).

The link picker lists every recorded link in document order under a `LINKS N`
header, grouped by report section, opening on the current page's first link
when the Highlights page is known. Rows show the label first and the site and
path second, with the page on the right (a `●` marks current-page links). A
well below the rows shows the URL to copy, wrapped with its host
emphasized; while Option is held the header gains `· Markdown` and the well
shows the Markdown form. Return copies the URL, Option-Return its Markdown
form, `1`–`9` copy that visible row, `A` copies every distinct URL one per
line (Option-A as a Markdown list), and Escape returns to the card. Pressing
`L` while its row is hidden explains why: links not yet recorded
(`bob ref recatalog`), an older bob without `ref links`, or saved Markdown
missing on this Mac. `L` typed before the links arrive queues like `C`.

Home-folder paths copy with `~` (for example, `~/bob/lib/…`); only the
Obsidian link and the PDF and narration file copies stay absolute.

Hold Option (⌥) to swap previews in place: Option-W a titled wiki link,
Option-P the absolute PDF path, Option-N the full `~` note path, Option-F the
narration file, and Option-1–9 the highlight's quote verbatim. Rows without
an alternate keep their payload. Option-click and Option-Return copy the
displayed alternate too. A queued copy remembers whether Option was held;
Return retries the same payload after a failed write.

Each row previews the exact value it copies. A shared marker ID shows its
`shared ×N` count; press `N` to copy this note's path. If the installed Bob
does not report `marker_id`, `I` explains that a newer Bob is needed and the
other rows still work. A successful copy hides Refs and shows a glass HUD.
Over a Capture draft, Capture returns with that draft. A
failed write leaves the card open so Return can retry.

### Rename card

Command-Shift-R or Rename… in the ⌘K menu opens a card for the selected
reference. Edit the filename stem; the `.pdf` suffix stays fixed. Return
runs `bob ref rename` for the selected note, and Escape closes the card.
Ordinary typing and editing shortcuts stay in the filename field. Bob's
refusal message and hint appear inline, and the draft stays editable for
another attempt. The card explains that the note and inbound links move
with the PDF while the reading task keeps its identity. Close the PDF in
Highlights first. Hiding the panel does not cancel a rename already in
progress; completion while hidden posts a notification.

### Link to Today card

Command-N or Link to Today… in the ⌘K menu opens the selected reference's
Pomodoro picker. Bob supplies the open Pomodoros, the current or next
default, and each preview; Return links to the default, while typing
filters rows and offers a new Pomodoro name. Arrow keys move through
matches, Shift-Return creates or reuses the exact typed name, and clicking
a row links it. The card stays open while choosing another reference.
The selected row gains its Now pill immediately, then the library refresh
replaces that optimistic pill. A successful (non-guarded) link from Bob Refs
marks that row seen, so it leaves NEW on the next unfrozen ranking. A glass
toast confirms the lane and ledger change; if the panel was hidden when Bob
returned, Bob Refs posts the same outcome as a system notification. VoiceOver
announces visible successes. Escape closes the card, and a link already in
progress finishes if the panel hides.

### Opening Bob Refs

- From anywhere on the Mac, Control-Shift-Command-O toggles the panel.
  Settings › References can turn this binding off.
- While Highlights is frontmost, Command-O opens Bob Refs instead of
  Highlights' Open… dialog. Settings can switch the takeover to
  Control-O or turn it Off. The takeover registers only while
  Highlights — or the override app picked in Settings — is frontmost,
  so Command-O and Control-O keep working everywhere else, and
  Highlights' File › Open… still opens its own dialog. The panel never
  activates, so Highlights stays frontmost and the same key closes the
  panel again.
- While Highlights is frontmost and Bob Refs is hidden, Command-T opens
  Bob Refs in Tabs (default) from fresh defaults with the focused PDF
  selected. Settings › References can change this key to Shift-Command-O,
  Command-E, or Off. It registers only for Highlights or the override app;
  the global Control-Shift-Command-O and Command-O library flows are
  unchanged. While Bob Refs is showing, Command-T switches between Tabs and
  the library instead of closing the panel; Escape closes it.
- While Highlights is frontmost and Bob Refs is hidden, Command-Y opens
  the Copy card on the focused PDF. Settings › References can turn this
  Off. It registers only for Highlights or the override app, and steps
  aside while Bob Refs is visible so the panel's Command-Y opens the card
  for the selection. Keys typed before the PDF is known replay on the card.
- Ordinary shows restore the remembered query, scope, filters, selection,
  revealed pages, and scroll positions, except when a newly added reference
  resets the view and selects it (including an arrival in the first 10
  seconds of an untouched show). A Ctrl+Tab switch always restores the
  remembered view and never resets for an arrival. The Highlights Tabs key
  opens from fresh defaults with Tabs on and the focused PDF selected, and
  nothing there is remembered. A Tabs show defers a new-reference reset to
  the next ordinary show. Ctrl-C resets the view to fresh-launch defaults.
- Clicking a scan notification opens the default view with Just scanned
  at the top and its first row selected. Clicking an open-PDF update
  notification opens Bob Refs and selects that reference when it is in
  the catalog.
- The menu-bar item offers Bob Refs… directly below Capture, with the
  same shortcut shown for display.
- Only one Bob panel is ever visible: opening Refs while Capture is
  open retains the capture draft first (`BobPanelCoordinator`), and
  opening Capture hides Refs. Ctrl+Tab switches between the panels
  through the same coordinator.
- Every successful capture refreshes Today and marks the snapshot
  stale, so the next open re-reads it. Recheck Bob re-points the Refs
  fetcher, restarts its watcher, and refreshes the snapshot alongside
  the capture ones.
- Settings › References also shows the resolved Highlights app (name,
  version, and path, or "Not found"), with Choose… (limited to `.app`)
  and Use Default, plus Reset Open History… behind a confirmation
  dialog. It also sets Preview highlights per page (1–20, default 5) for
  the inspector, or
  `defaults write org.bobs.bob-mac-capture refsInspectorNotesPageSize -int 5`,
  and the "Tell me when Bob updates an open PDF" toggle (on by default;
  off suppresses notifications only).
- Diagnostics: a failed global or takeover registration reports
  "Refs hotkey conflict: …"; free the shortcut and use Recheck Bob.
  Toggling the References settings re-registers immediately.

### Tabs

Tabs lists every document open in Highlights. A matched tab uses its
reference note row. A collision or a file outside the library stays in
the list as a dim row with its filename and a clear match status.

Press Command-T while Highlights is frontmost and Bob Refs is hidden to
open Tabs; Settings › References can change this to Shift-Command-O,
Command-E, or Off. Inside Bob Refs, Command-T toggles Tabs; the filter
combines with kind scopes and keeps the current query. The current tab
comes first; the rest follow most-recently-active order, tab-bar order
breaking ties, unmatched tabs last. Every Tabs preselection selects the
focused PDF.

A Tabs show keeps the selected row while that tab is still open. Every
Tabs show preselects the focused PDF. Command-T from Highlights opens from
fresh defaults and is never remembered.

Return, Tab, or double-click switches to the existing tab. Switching
keeps its page, does not change reading state, and does not add an entry
to the open log. On a collision or unmatched Tabs row, Command-Return and
Control-Return show the same warning instead of opening. Control-X closes the selected tab, including collision
and unmatched rows: the row folds out, the next row is selected, and the
panel stays up for repeated closes.
Hovered and selected Tabs rows also show a Close Tab button (⌃X).
A background tab closes by briefly switching Highlights to it, closing it,
and switching back.
Closing the last open document also quits Highlights, and the panel
hides. Shift-Command-T reopens the most recently closed tab (up to 20,
kept in memory for the app's lifetime). A matched row reopens its library
PDF; a collision or unmatched row reopens only when its full path was
known.

If Highlights already closed the tab, the row stays gone with no error.
If a save sheet appears instead of closing, Bob Refs hides so
the sheet is in front. Any other failure restores the row, selected,
with "Couldn't close “title” in Highlights."

Tabs refreshes on panel show, Command-T, or Command-R;
it does not poll in the background. The panel explains when Accessibility
permission is needed, Highlights is not running, no documents are open,
or a read fails.

Accessibility reads Highlights' window and tab attributes, selects a
tab through its button, and presses a window's close button.
Names stay in memory. Highlights exposes the
visible tab's full path; background tabs match by filename only. Tabs in
other Spaces and full-screen windows are untested.

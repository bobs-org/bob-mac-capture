---
title: "Mac Capture idle agenda"
description: "Today's Pomodoro agenda in an empty Bob Mac Capture draft: caching, folds, and keys."
---

## Idle agenda

[![Idle agenda showing the running FIX Pomodoro, linked tasks, and upcoming sessions](images/capture-agenda.png#only-light)](images/capture-agenda.png)
[![Idle agenda showing the running FIX Pomodoro, linked tasks, and upcoming sessions](images/capture-agenda-dark.png#only-dark)](images/capture-agenda-dark.png)

Synthetic CI render. Open the image for full-size text.

With an empty draft, the panel shows today's Pomodoro agenda below the editor, in
the same thin-material pane as the live preview. It lists the running Pomodoro (Now)
and every future one (Next, then Later), each with its linked tasks at the most
detail that fits below the fixed eye line without scrolling. Unnamed entries show
the derived `homes.label` from `bob capture-pomodoros --tasks` (secondary style)
instead of "Untitled Pomodoro"; named entries keep their authored name and, when
bob supplies a chip, a muted home chip with an area-hue dot. The one-row fold and
the Later strip use the same names. An older bob that omits `homes` is unchanged. Keep source links in
those task titles and details display as a lightbulb. The `x` and `=`
numbers match the ones `bob` will use: the current entry shows its `x` numbers and
every other open entry shows its `=` lineup number.

The row directly under `Today` shows the saved daily meters (`Themes N/C` and
`Links N/C`); their caps come from bob's plan config. An older `bob` that omits
`plan_budget` simply omits this row. A typed capture preview still shows the proposed
budget for that draft. Plan-config edits appear on the next ordinary agenda refresh,
including the next panel show.

- Freshness and caching. `bob` owns every fact via
  `bob capture-pomodoros --format json --tasks`; the app caches the last good
  snapshot in memory and revalidates it on launch (prefetch after prewarm), on
  filtered vault events (visible `.md` notes and the Tasks-plugin filter — never
  `.git/`, attachments, or settings churn), on every panel show
  (stale-while-revalidate, replacing the old per-show spawn), after each successful
  submit, on wake, unlock, day change, and clock change, and fresh after Recheck Bob
  or a `bob` executable or directory change. One refresh flies at a time with at most
  one follow-up; byte-identical output publishes nothing. A snapshot whose date is
  not today is never shown ("Loading today…" until the refresh lands); a failed
  refresh keeps the last good agenda and marks the title row "Couldn't refresh". An
  older `bob` without `--tasks` hides the agenda and serves only the close-comma
  count until Recheck Bob or an executable change.
- Folding. Detail fades with distance: the farthest Pomodoros lose their logs first,
  then collapse to one line per task, one row per Pomodoro, and finally into a Later
  name strip. Every fold leaves a chip (`⚒ 3`, `🗓 2`, `🥀 1`, `+5 lines`, `4 tasks`)
  that expands
  that unit in place; expansions reset on hide and on snapshot change, and pinned
  units may overflow with a scroll and an `N more` cue.
- Transitions. No animation on show — cached content is in the first frame. The first
  keystroke dims the agenda to 35% (100 ms, instant under Reduce Motion) and holds it
  until the preview settles, another owner takes the region, 250 ms elapse, or the
  draft returns to blank; the region then swaps with one height change. In-place
  agenda updates cross-fade (120 ms, off under Reduce Motion); height is never
  animated. Clearing to empty repaints the cached plan instantly and revalidates in
  the background; an in-flight Preview, leftover preview card, error, or pending-list
  notice is retired with the draft so none of them can keep the agenda hidden. The Now
  countdown (`12m left`, `ending now`, `overdue 8m`) ticks at
  minute granularity while the panel is visible.
- Setting and diagnostics. Settings › Agenda toggles "Show today's Pomodoros when the
  draft is empty" (on by default); while off, the store keeps refreshing for the
  close-comma count but nothing is measured, planned, or shown. The same section
  reports "Last refreshed 14:32", "Couldn't refresh: …", or the old-`bob` upgrade
  hint.
- Accessibility. Each Pomodoro group is one container ("Running Pomodoro FIX, 14:10
  to 14:35, 2 tasks"); the countdown is the header's value, not its label. Task rows
  read "Task 1, In Progress, …" and chips announce what they expand. Return in an
  empty editor never acts on an agenda row, and keyboard focus never leaves the
  editor.
- Signposts. Intervals `agenda-refresh`, `agenda-measure`, `agenda-plan`,
  `refs-panel-show`, `refs-panel-prepare`, `refs-panel-order`, `refs-pull`,
  `refs-refresh`, and `refs-scan`, plus events
  `agenda-unchanged`, `agenda-published`, and `agenda-hold-released` — metadata only
  ([Diagnostics](diagnostics.md#signposts)).

The store behind the agenda runs on the shared Pomodoros lane; see [Architecture](https://bobs-org.github.io/develop/mac-capture/architecture/). Signposts and Recent Activity are in [Diagnostics](diagnostics.md).

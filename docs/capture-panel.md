---
title: "Mac Capture panel"
description: "Panel lifecycle, editor, layout, submission, live preview, and clipboard semantics for Bob Mac Capture."
---

The panel owns presentation, process orchestration, and the hotkey. Capture grammar, completion data, previews, and vault mutation stay in `bob` ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)). Pickers have their own pages ([overview](pickers.md), [task pickers](task-pickers.md), [relationship pickers](relationship-pickers.md)); rendered output is in [Capture previews](capture-previews.md), keys in [Keyboard](keyboard.md), the subprocess contract in [Protocol](protocol.md), and the implementation in [Architecture](https://bobs-org.github.io/develop/mac-capture/architecture/).

## Panel

- Bundle identifier: `org.bobs.bob-mac-capture`.
- App type: `LSUIElement` resident menu-bar app.
- The menu-bar icon's menu offers Capture, Settings, Recheck Bob, Restart Bob Mac
  Capture, and Quit Bob Mac Capture, in that order, plus a conditional
  `bob Not Resolved — Open Settings…` row (with a separator) while `bob` is
  unresolved. Restart discards an unsent draft;
  retained canceled drafts survive Restart and Quit. There is no confirmation dialog.
  Restart refuses to quit (reporting a failure instead) when the running process is not
  launched from an installed `.app` bundle or that bundle no longer exists on disk. See
  [Install](install.md#updating-reinstalling-and-rollback) for automatic install restart and the
  manual Restart item.
- Production hotkey (the default): Control-Shift-Command-I.
- Development/rollback hotkey: Control-Shift-Command-R, selectable in Settings.
- The hotkey path uses a pre-warmed non-activating `NSPanel`; subprocess work is kept
  off that path. A show (hotkey or Ctrl+Tab) skips re-spawning `capture-targets` when
  the last targets refresh started less than 5 s ago; vault watchers, Recheck Bob,
  launch, and failure recovery always refresh. The idle agenda still revalidates on
  every show.
- A fresh popup is a compact bar — a one-line editor plus persistent footer actions.
  With an empty draft, the auxiliary region below the editor shows today's agenda
  (see [Idle agenda](idle-agenda.md)); with the agenda off or nothing to show, the popup is the
  compact bar exactly as before, with no empty preview placeholder and no dead
  space. Its first frame uses a conservative compact fallback only until SwiftUI
  reports rendered editor, auxiliary, and footer metrics. After that, the window's
  height tracks measured content as the editor grows with the draft, the completion
  list appears, the live preview arrives, and errors show or clear. Every show
  places the panel at a fixed eye line: the compact panel's top is what AppKit's
  center() gives it, cached once per
  screen, so the input line lands in the same place with or without the agenda or a
  retained draft. The agenda never moves the editor — the rendered pane and the
  reported auxiliary height share one viewport derived from the measured plan bounded
  by the below-eye-line budget plus the pane padding once, so a cached plan paints
  synchronously with no zero-height frame and a zero budget stays bounded instead of
  unbounded — and typed previews keep growing downward from the
  same top under today's clamp and slide-up rule. Measured
  heights include the titlebar safe-area inset of the full-size-content panel, so
  the applied content height already accounts for the titlebar strip SwiftUI lays
  out inside. The editor's ceiling is a screen-derived budget — the visible frame
  minus margins, persistent chrome, and a reserved minimum for the auxiliary
  region — not a fixed line count.
  The window's ceiling is the screen's visible frame minus the 24 pt margins. Resizing
  is instant and unanimated so the content and window never desynchronize. Height is
  content-owned and not user-draggable; width remains user-resizable and reflows the
  editor, which is the one case that legitimately changes the content height.
  Completion, destination, preview, and error details live in the auxiliary overflow
  region. When the budget binds, the editor scrolls internally, that middle region
  keeps its reserved minimum and scrolls, and the footer actions always stay visible.
  The canceled-draft stash picker grows the panel to show its fixed **Shift-D Delete
  All** action and up to five draft rows; longer stashes scroll only the row viewport,
  and screen-constrained layouts preserve the fixed picker action before row height.

Canceling or completing the prompt restores focus to the capture editor. The editor starts at one visual line and grows and shrinks with rendered content up to a screen-derived budget, then scrolls internally for longer drafts.

## Editor

- Editor highlighting is derived from `bob capture-parse --format json` spans. The app
  validates UTF-8 byte ranges and ignores a malformed span set instead of applying a
  partial grammar view. Every span kind — capture markers and the five Obsidian wikilink
  kinds (`wikilink_delimiter`, `wikilink_target`, `wikilink_heading`, `wikilink_block_id`,
  `wikilink_alias`) — resolves through the single palette in `CaptureEditorPalette`.
  The close-list spans `pomodoro_close_in_progress` and `pomodoro_close_complete`
  render orange and green, sharing the badge colors of the rows they select; the
  whole-item completion spans `task_complete_sigil` (green, the same complete-green
  as `x!`), `task_complete_note` (route), and `task_complete_block_id` (block ID)
  reuse those existing colors, so the editor and the completion card never disagree
  about what a completion is;
  `pomodoro_close_drop` renders muted gray. The Work Log index span
  `pomodoro_close_log_index` renders cyan, sharing the tint of the typed entry
  line it lands on in the close card; it is not a completion span kind.
  The editor also auto-inserts `,` between close task numbers: typing `1`–`9`
  right after a task number in a close list inserts the separator itself
  (`x1` + `2` → `x1,2`). Backspace immediately after an auto-inserted
  `,<digit>` removes both characters together (`x1,2` → `x1`); a manually
  typed or pasted comma stays native. The in-memory agenda store runs
  `bob capture-pomodoros --format json --tasks` on one shared lane: a
  prefetch at launch, filtered vault events (visible `.md` notes and the
  Tasks filter, never `.git/` or attachments), every panel show as
  stale-while-revalidate, after each successful submit, on wake, unlock,
  day change, and clock change, and fresh after Recheck Bob or a bob
  executable or directory change. One refresh is in flight at a time with
  at most one follow-up, byte-identical output publishes nothing, and a
  snapshot whose date is not today is never shown. An older bob without
  `--tasks` hides the agenda and serves the count from plain
  `capture-pomodoros` until Recheck Bob or an executable change. The
  close-comma count follows the store: it is nil when the snapshot is
  not today's or the latest refresh failed. The assist runs only when the running
  Pomodoro has fewer than 10 numbered Task Links; an older bob without the
  field disables it. Replacing or clearing the Bob client invalidates
  in-flight counts and assist parses so a stale count never re-arms the
  assist. The decision uses bob's `capture-parse` close-list spans,
  so the app still never recognizes close syntax itself. Known limitation: a
  batch that links several new tasks before its `x` can push a 9-link session
  past 10.
  Global destination spans (`global_route`, `global_sub_bullet_route`, and
  `global_sub_bullet_block_id`) reuse the existing destination and block-ID colors, so
  the editor and the completion list never disagree about what color represents what
  syntax.
  `template_header` shares the route color; each `template_placeholder` and
  `template_field` uses the same slot hue, selected by `field % 6` from orange, teal,
  pink, green, purple, and brown. Template diagnostics underline their typed ranges in
  red; ordinary drafts keep their existing highlighting.

The agenda UI behind the store above is described in [Idle agenda](idle-agenda.md).

## Inline completion

- Inline completion calls
  `bob capture-complete --all-tasks --cursor BYTE --format json -- <draft>`; accepted
  ordinary candidates apply the server-provided byte replacement range and
  `cursor_after` exactly, restoring a collapsed caret at that offset. Route completion
  also covers the route side of Bob's `@route^block-id` ordinary task-with-ID marker and
  the route side of a `@@route` or `@@route+block-id` declaration anywhere in the draft.
  A single leading `@` and its still-typing route fragment also remain
  completion-active before the draft has enough syntax to be submitted as a routed
  capture, so an empty editor can complete the marker-only task-toggle form
  `@route+block-id` entirely from the keyboard. Cached route completion strips the
  complete `@@` sigil just like Bob's server response. The authored ID side never
  uses the inline list: the right-hand side of `@route:` and `@route^` opens the
  Block ID Picker instead (see [Task pickers](task-pickers.md)).
  A Bob `template` candidate for `@@te` or `@@` is shown as the `@@template:` directive
  with Bob's label beneath it; accepting inserts Bob's replacement verbatim. The `+`
  shortcut does not accept this header candidate.
  While route completion is visible, typing `+` directly after the route text accepts
  the selected route and keeps the `+`: an exact typed route (case-insensitive) is kept
  as typed, otherwise the selected candidate's route is spliced in, and the task picker
  opens immediately without pressing Return first.
  Typing a bare `@@` after an item-local `@route` or `@route+block-id` marker calls
  `bob capture-rewrite --cursor BYTE --format json -- <draft>` immediately on its own
  lane. When Bob rewrites the draft, the app applies the returned text and cursor only
  if the visible draft still matches the submitted draft, announces Bob's summary, and
  reruns parse/preview. When Bob cannot absorb a marker such as `@route#Section`,
  `@route^block-id`, `@route:block-id`, or a Pomodoro-note `#`, the app leaves the draft
  untouched and announces Bob's notice.
  Typing a third `@` immediately after a first physical line that is exactly
  `@@` asks bob to start a template through the same rewrite lane. This gesture
  needs a bob build that implements `start_template`; with an older bob, the
  third `@` remains literal.
  Typing `^` immediately after a complete `@route:id`, or `:` immediately after
  `@route^id`, uses that same rewrite lane. Bob decides whether the marker is
  eligible; the app forwards the post-key draft and caret. A matching reply
  consumes the new character, swaps the separator, and leaves the caret after
  the unchanged ID so the keys can be repeated without moving backward. The
  new key must sit against the ID, and only those two plain forms toggle —
  space, suffixes (`#name`, `+`, `=`), `@@`, `@!`, and other marker families
  type through. Undo restores the literal post-key draft. When Bob leaves the key
  alone (for example `@route:` or `@route^` with no ID yet, or a whole-item `^`), the
  keystroke behaves like ordinary typing, and its picker or completion opens as before.
  This gesture needs a bob build that implements `switch_block_id_separator`.
  Typing `|` after a `~note:id` or `~~note:id` uses that rewrite lane too.
  Bob glues the pipe to the token when spaces or tabs separate them, then the
  completion response opens the relation card. Undo restores the literal
  post-key draft. This gesture needs a bob build that implements
  `attach_relation_label`; with an older bob, the space before `|` remains.

## Drafts

What you can type in the editor. The canonical token contract is [Capture syntax](https://bobs-org.github.io/reference/capture-syntax/); the app colors the span kinds `bob` reports, asks `bob` for completion at the real caret, and never parses punctuation itself.

A draft is one or more capture items separated by one or more blank or whitespace-only
physical lines, with an optional global destination declaration token anywhere in the
draft. A declaration is exactly one `@@route` or `@@route+block-id` token; it routes
otherwise-unmarked items to `route.md`, or beneath `^block-id` in that route. A line
containing only `@@...` declarations is metadata rather than a capture item. Any local
item marker still wins for that item, and if the same item also declares a global
destination, Bob reports a shadow warning instead of guessing. Unsupported `@@` forms
are Bob diagnostics rather than literal task text. Typing a bare `@@` inside an item
that already has an absorbable `@route` or `@route+block-id` marker moves that reference
onto the `@@`; non-absorbable markers such as `@route#Section`, `@route^block-id`,
`@route:block-id`, and bare `#` produce an explanatory notice without changing the
draft. Within each item, the first nonblank line is the parent, followed by zero or more
authored `-`/`*`/`+` bullets. Column-zero bullets become first-level authored children;
bullets prefixed by exactly two ASCII spaces become nested authored children under the
nearest preceding first-level authored child.
A marker (`@route`,
`@route+block-id` alone to ensure Next and relocate an existing Task Link,
`@route+block-id#pomodoro` alone to ensure Next onto a named Pomodoro,
`@route+block-id!` alone for the explicit two-way task-toggle item,
`@route+block-id` with body text for an
existing-task sub-bullet, `@route+block-id#section` to nest under one of that task's
ALL-CAPS section bullets, `@route^block-id` for an ordinary task with an authored block
ID, `@route^block-id+#pomodoro` for a project note (with ` :id` / ` ^id` tokens
on its task bullets naming and optionally linking project tasks),
`s:<N>`, `$<N>`, `%`, …) at the end of any valid line configures that item even
when it appears on a child line. The app never parses that punctuation itself:
highlighting and completion follow bob-cli's semantic spans. Both families complete
their route side; only the `+` family's right-hand side offers existing tasks, `#` after
a resolved `@route+block-id` offers Pomodoro names while the item has no body text and
task sections once it does, and the `^` family's authored ID opens the New ID picker.
A project note's ` :id` bullet becomes a Next task linked into the Pomodoro and its
` ^id` bullet a named task; the preview names each linked task and the notification
reports "Linked N tasks into …". The retired
`@route::block-id` and `@route:block-id+` spellings are parse diagnostics from
`bob capture-parse`, not supported interactive forms.

```text
Prepare the launch review
- Confirm the rollout owner
  - Send the owner the final date
- Attach the final checklist @work $1
  - Verify the links

Write release note @notes#Ideas
```

```text
@@foo
First task

Second task @bar
```

```text
First task
- Child detail @@foo

Second task @bar
```

Bob's routed marker syntax works directly in the editor. `@route^block-id` captures an
ordinary `[ ]` task with a trailing `^block-id` and no Pomodoro task link, while
`@route:block-id` keeps the Pomodoro-linked next-task behavior. When that existing
task is Blocked only by its own open prerequisites, Bob drops those links and then
links; the preview shows a `dropped dependency on …` chip, or `dropped N
dependencies` when several go. A refused drop — the task's project is blocked, the
target is a `^prj`, its Depends-On line needs repair, or several `[scheduled::]`
fields still block it — keeps the task unlinked and the preview shows Bob's
not-linked sentence with the promoted prerequisites. `@route:block-id#name`
targets a named open Pomodoro by slug, and `@route:block-id=<X>` or
`@route:block-id#name=<X>` atomically starts that session (`<X>` mirrors the
`se<X>` snippet; empty is 25 minutes). The `=<X>` suffix highlights as its own
`pomodoro_start` span, never offers completion inside the suffix, and keeps
`#name` completion ranges ending before `=` so accepting a name never erases a
typed duration. Preview renders Bob's resolved session — selected Pomodoro,
5-minute-rounded start/end, duration, and created-entry state — sourced only from
`bob capture --dry-run --no-clip --format json`, and submission runs the same Bob
command; conflicts such as an already-running session surface as ordinary preview
errors. A whole-item `+[N]`/`-[N]` draft adjusts the current Pomodoro instead
of capturing a task: each unit is 5 minutes (`+5` extends by 25 minutes), the
count defaults to 1 (a bare `+` is one unit), subtraction clamps at zero and
reports requested versus applied minutes, and the item must contain only the
signed count. The `+N` token highlights as its own `pomodoro_adjust` span and
never offers route or task completion. Preview renders Bob's resolved
before-to-after timing, signed minute effect, and target line — sourced only
from `bob capture --dry-run --no-clip --format json`, including in mixed
drafts — and submission runs the same Bob command; a missing or ambiguous
target surfaces Bob's error as an ordinary preview failure. A whole-item
`++[N]`/`--[N]` draft shifts the whole running session instead of capturing a
task: each unit is 5 minutes (`++3` moves 15 minutes later), the count defaults
to 1 (a bare `--` is one unit earlier), the duration is unchanged, and the item
must contain only the operator. The `++N` token highlights as its own
`pomodoro_shift` span and never offers route or task completion. Preview renders
Bob's resolved before-to-after timing, minute effect with later/earlier, and
target line with a double-chevron row — sourced only from
`bob capture --dry-run --no-clip --format json`, including in mixed drafts —
and submission runs the same Bob command; the footer says **Shift** and the
notification summarizes the same returned shift. A whole-item `=`/`=<X>`
starts the next future Pomodoro instead of capturing a task: empty is 25
minutes and `<X>` mirrors the `se<X>` snippet, the item must contain only the
operator, and the `=` token highlights as its own `pomodoro_start` span and
never offers route or task completion. Preview renders Bob's resolved session,
day-file destination, and queued Task Links — sourced only from
`bob capture --dry-run --no-clip --format json`, including in mixed
drafts — and submission runs the same Bob command; the footer says **Start**
and the notification summarizes the same returned start. The same `=` token
overrides the running Pomodoro when one is open: `=` / `=<X>` restarts it now
with fresh `se<X>` timing, and `=#name` swaps that Pomodoro in (taking over
the running ledger unless a timing is given) while the old session returns to
first future. Preview renders an orange override banner plus Bob's resolved
before → after range and demoted row — sourced only from
`bob capture --dry-run --no-clip --format json` — with a **Restart** / **Swap**
footer tinted orange and matching notifications. An override commits only after
its warning was on screen. Claimed `==` is a retired teaching error. Type `x`, a blank
line, then `=` to close the running session and start the next one in a single
draft. A whole-item `x` closes
the running Pomodoro; `@route:block-id=x` links an existing task first (dropping
own-prerequisite Blocked edges the same way `@route:block-id` does; a refused drop
keeps today's history link), and
`<text> @route:block-id=x` creates a task inside that session before closing it.
Appending task numbers chooses each Task Link's outcome: `x2` keeps only 2 in
progress, `x!2` completes 2, `x1!2` does both, and a note-free `x0` resets the session to first future while a note-bearing `x0` defers all (single-quote tokens containing `!`, `*`, or `~` in zsh). The same suffix works on link
forms. Work Log bullets log while closing: type `x`, then `⌃J` for a `- ` bullet,
then either `1 wired the lexer` to add `wired the lexer` under link 1, or just
`wired the lexer` to let Bob file it by position — unnumbered bullets log in
order to the close's worked tasks, and a single worked task takes them all —
before the unchanged close writes it to that task's Work Log; `⌃J` then `Tab`
nests a `  - …` detail under the entry, `⌃J` then `⇧Tab` starts the next entry,
and `⌫` on a bare `- ` row deletes it. Bullets are numbered all or none, and
a leading number is always a task number, so `- 1 fixed 3 bugs` needs no escape
(to log text that starts with a number, number every bullet). Numbered entries
get a cyan index chip matching the card's new entry line, while positional
entries get none. Text on the `x` line itself still takes an inline entry
(`x wired the lexer` logs to task 1): it shows the bullet to write instead. A trailing `~<K>` drop list on a whole-item start (`=~2`, `=3~2,4`,
`=#bugs~2`) starts the next session without those numbered queued Task Links —
`~` drops, so `=~2` drops task 2 from the session you start the way `x~2` drops
task 2 from the session you stop, using the numbers the start card shows. The
start card numbers every queued row, strikes and dims dropped rows in place with
a `Dropped 2` summary, and teaches `Type ~2 to drop task 2` until a drop is typed.
The
dedicated close preview shows Bob's session timing, task transitions, Work Log entries
with their details, and next session. A close that unblocked dependents gains an
**Unblocked** section under the task rows with the same row views as the `!` card
(destination capsules, minted-ID and reason captions, muted still-blocked rows).
The footer says **Close**, and the notification summarizes the same
returned close plus the one successor line when anything was linked. Missing or ambiguous running sessions surface Bob's error in the
preview. A list left dangling on `,`/`!`/`~` is an editing state, not an error: the
card stays live on what is typed so far with **Close** disabled until a task
number follows; a dangling Work Log bullet (`x` plus `- 1`) previews the rest
dimmed with `Type the Work Log entry for task 1` and keeps
**Close** disabled; a start list left dangling on `~`/`,` previews the trimmed start
the same way with **Start** disabled instead. A marker-only `@route+block-id` ensures that existing task is Next and
relocates its Task Link (dropping own-prerequisite Blocked edges the same way
the `@route:block-id` link does; a refused drop stays unlinked and the preview
shows Bob's not-linked sentence), `@route+block-id#pomodoro` does the
same onto a named Pomodoro (creating the named future Pomodoro if needed),
`@route+block-id!` is the explicit link-presence toggle: it links an unlinked
task (Ready and a task Blocked only by its own prerequisites rise to Next after
those prerequisites are dropped; other Blocked tasks stay unlinked and the
preview shows why; Next and In Progress keep their lane)
and unlinks a linked task without touching the lane, and `@route+block-id` with
body text nests beneath the task. `@route+block-id#section` nests under that task's
matching section bullet once body text is present; the same `#` position opens the
Pomodoro-name popup while the item is still marker-only, including the
create-future-Pomodoro row and **Name Pomodoro** prompt. The app labels Ensure Next
versus Set Next/Open from Bob's returned `toggle_behavior`, never by parsing `#` or `!`. The `@route+` parent-task picker (and the vault-wide `+` picker) plus Add block ID prompt are still how a task
without a block ID becomes selectable. The app does not duplicate those grammar rules; it
colors the span kinds Bob reports, asks Bob for completion at the real caret, and
submits the original draft text.

## Live Preview and Clipboard Semantics

The continuously updated preview below the editor calls
`bob capture --dry-run --no-clip --format json` on every debounced edit and never reads
the clipboard. Bob still claims an eligible URL-only reference ending in exact `%` as
a companion-audio request: `https://arxiv.org/pdf/2609.12039 %` stays a reference
while you type. Ordinary `%`, `%N`, and `%header` clipboard spans stay literal. Pressing
the explicit **Preview** button or **Capture** resolves the clipboard and
Clipy history normally, exactly as the final capture would. A `$<N>` random
schedule is rolled once per
draft and reused by every subsequent live preview and by the final submission, so the
displayed scheduled date always matches what gets written.

## Submit

A successful aggregate capture hides the panel automatically only after Bob returns
  success for the whole draft; a failed capture keeps the panel open with its complete
  draft and an actionable error. Control-Return opens Bob's `open_notes` through one
  `bob-open-notes` URL, which opens tabs and lands on each captured line. This needs
  bob-navigation-hotkeys ≥ 2.44.1; an older plugin ignores the unknown
  `bob-open-notes` action, so nothing opens. An older bob that omits `open_notes`
  still opens the notes as tabs, but without landing.
  Reopening the panel after a success starts from a clean slate — the prior
  "Captured → …" summary and status text are cleared, while a retained draft (from Escape
  or a failure) reopens exactly as it was left. Escape retains a nonempty draft.
  A Ctrl+Tab switch retains the draft and caret exactly like Escape.
  **Discard** permanently clears the draft without stashing, while Control-C always
  clears it: it stashes a semantically nonempty draft first, except a Task Go-To (`/`)
  draft is deliberately discarded and nothing is retained when stashing is off
  (capacity 0).

## Canceled drafts

Canceled drafts persist across Quit, Restart, crash, and logout in
  `~/Library/Application Support/org.bobs.bob-mac-capture/canceled-draft-stash.json`
  (`schemaVersion` 1, newest-first array order). The directory is mode 0700 and the file
  is mode 0600. Settings persists only the capacity (in `UserDefaults`), defaults it to
  10, and clamps it to 0...36. Zero turns the feature off and deletes the file. Capacity
  reductions keep the newest entries and drop older overflow. Repeated cancellations are
  retained as separate entries, even when their text is identical. Settings also shows
  the retained count and a confirmed **Clear Stash...** action, which deletes the file.

## Stash

The footer's **Stash** action shows the number of retained canceled drafts and matches
Control-S. If the stash is empty, opening it reports "No canceled drafts yet" without
logging draft text. If the editor currently contains any characters, the picker refuses
to open; capture, retain, cancel, or explicitly discard the live draft first so restore
can never overwrite work. **Discard** is intentionally different from Control-C: it is a
permanent discard and never adds an entry to the stash. Control-C on an empty or
whitespace-only editor, on a Task Go-To (`/`) draft, or when stashing is off
(capacity 0) closes without adding an entry.

While the stash picker is open, it is modal inside the panel's auxiliary region and
uses the same compact material style as completion. Rows are newest first. Restoring a
row installs that exact text in the empty editor with the caret at the UTF-8 end, removes
only that restored entry from the stash, keeps the panel open, and starts normal
parse/live-preview analysis. This is a pop operation: non-restored entries remain in
order. Pressing uppercase `D` with Shift-D or Caps Lock, or clicking
**Shift-D Delete All**, immediately clears every retained canceled draft permanently,
including the on-disk file, closes the picker, leaves the panel open with an empty
editor, and reports only "Canceled draft stash cleared". Lowercase `d` does nothing

## Open chip

When Capture is enabled, the footer shows a **⌃↩ Open** chip just before the primary
button whenever the live preview's open plan is non-empty, and also while this draft
still has no preview. A queued link whose plan is empty hides the chip. Clicking it
captures and opens Bob's reported notes. Hold Control alone (no other modifier, no
key) for 400 ms to tint the chip and fade in a destinations capsule above the footer's
trailing edge — "Opens in Obsidian", then up to four rows with a note or calendar
glyph, label, and optional `line N`, then `+N more`. The capsule uses the completion
list's material and shadow so the footer never reflows; Reduce Motion crossfades
without the 4 pt rise. VoiceOver reads the destinations from the chip; the capsule is
hidden from accessibility. In a narrow panel the chip is the first footer control

Related: [Protocol](protocol.md) (executable resolution, timeouts, guard flags), [Architecture](https://bobs-org.github.io/develop/mac-capture/architecture/) (lanes, caches), [Fix Mac Capture when bob is not resolved](https://bobs-org.github.io/guides/fix-mac-capture-bob-resolution/), and [Recover a stuck Mac Capture panel](https://bobs-org.github.io/guides/recover-mac-capture/).

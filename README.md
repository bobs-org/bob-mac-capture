# Bob Mac Capture

Native macOS 26 menu-bar capture app for Bob. The app owns presentation, process
orchestration, the global hotkey, settings, launch at login, and packaging. `bob-cli`
remains the only implementation of capture grammar, preview, completion data, and vault
mutation.

## Requirements

- macOS 26 with Command Line Tools for Xcode 26+ or Xcode 26+.
- SwiftPM from the selected Apple toolchain. `justfile`, `Scripts/bundle.sh`, and CI all
  route Swift invocations through `Scripts/xcode-swift.sh`, which resolves `swift` via
  `xcrun` from `DEVELOPER_DIR` or `xcode-select --print-path` rather than trusting a
  bare `swift` on `PATH`. This accepts either `/Library/Developer/CommandLineTools` or a
  full Xcode developer directory when the selected tools provide a macOS 26+ SDK and
  Apple Swift executable. It also keeps a Swift.org / Swiftly installation, or any other
  shadowing `swift`, from compiling ordinary targets while `swift test` later fails at
  `import XCTest`. Compare what's actually selected:

  ```sh
  command -v swift; swift --version           # whatever is first on PATH
  ./Scripts/xcode-swift.sh --version           # what build/test/bundle actually use
  ```

  If the two differ, `./Scripts/xcode-swift.sh --version` fails, or `import XCTest`
  fails to compile, update or select matching Apple developer tools rather than
  migrating tests off XCTest:

  ```sh
  sudo xcode-select --switch /Library/Developer/CommandLineTools
  # or:
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  # or, scoped to one shell:
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  # or:
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```
- A signed or ad-hoc signed `bob` executable available at one of:
  - `~/.cargo/bin/bob`
  - `~/bin/bob`
  - `/opt/homebrew/bin/bob`
  - `/usr/local/bin/bob`
- A `bob` build that supports `@@route` / `@@route+block-id` global destination
  declarations anywhere in the draft, `capture-rewrite`, `capture-complete --all-tasks`,
  `capture-task-id`, `capture-pomodoro-name`, the `task_link` completion context for
  `:` picker queries (with `note_kind`, `block_id_suggestions`, `group`, `scheduled`,
  and `pulls_forward` candidate fields), the `task_parent` completion context for
  leading and prose-terminal `+` (with the additive `picker` descriptor:
  `kind: parent_task`, `scope: note|vault`, `scope_token`, `note_target`,
  `marker_range`, `trigger_removal_range`, optional `action_continuation_keys`,
  and top-level `query`), the same descriptor on scoped `@route+` `task` responses,
  `parent_replacement` on `capture-task-id` for vault-wide ID-less picks,
  `task_section` completion for
  `@route+block-id#`, `pomodoro_name` completion for `@route:block-id#` and bare
  task-toggle `@route+block-id#`, the `task_block_id` completion context for the
  `@route^block-id` ordinary task-with-ID marker, the additive top-level `block_id`
  object on both block-ID contexts (intent, marker range, body, allowed-character
  rule, used IDs, suggestions), the additive `creates_pomodoro`
  create-future-Pomodoro action, `task_toggle` capture JSON, the
  `task_toggle_*` parse spans, and the current task-toggle spellings:
  plain `@route+block-id` for Ensure Next relocation to the implicit
  current/next Pomodoro, `@route+block-id#pomodoro` for named Ensure Next
  relocation or named-future creation, and suffixed `@route+block-id!` for
  the explicit two-way toggle (`toggle_behavior` and
  `task_toggle_explicit_toggle`), plus the atomic-start `@route:block-id=<X>` and
  `@route:block-id#name=<X>` suffix (`pomodoro_start` parse/capture JSON and the
  `pomodoro_start` span, where `<X>` mirrors the `se<X>` snippet: empty is 25
  minutes, `-` offsets one 5-minute unit), plus whole-item `+[N]`/`-[N]`
  duration adjustments (`pomodoro_adjust` parse/capture JSON and the
  `pomodoro_adjust` span, where each unit is 5 minutes and subtraction clamps
  at zero), plus whole-item `++[N]`/`--[N]` session shifts (`pomodoro_shift`
  parse/capture JSON and the `pomodoro_shift` span, where each unit is 5
  minutes and the count defaults to 1, so `+`, `-`, `++`, and `--` all work),
  plus whole-item `=`/`=<X>` session starts (`pomodoro_start` parse/capture
  JSON and the `pomodoro_start` span, where `<X>` mirrors the `se<X>` snippet
  and the capture summary carries the session's queued Task Links),
  plus whole-item `=<X>#name` named starts (the `pomodoro_name` span over the
  name bytes, the `pomodoro_start_name` completion context with the additive
  `next_up` row marker, the `=#` incomplete state with its
  `interactive_placeholder` span, `=x#name` close near-miss diagnostics, and
  the additive `created_pomodoro` capture summary for new and "again"
  sessions),
  plus Pomodoro close `=x` and its additive `pomodoro_close` capture summary,
  plus the project-note `@route^block-id+#pomodoro` marker (the retired
  `@route:block-id+` spelling is a parse diagnostic), the trailing ` :id` /
  ` ^id` project-task tokens (`project_task_block_id` completion context with
  intent `new`, `project_task_link_marker` / `project_task_block_id` parse
  spans, and the additive `project_note.task_links` capture object).
  Older builds can still capture ordinary drafts, but
  global declarations, bare-`@@` absorption, the Add block ID flow, the Name Pomodoro
  flow, the task-section popup, and the task-toggle footer/preview report the local Bob
  error or an empty list until Bob is upgraded. An older Bob that returns scoped
  `@route+` `task` completion without the additive `picker` descriptor keeps the
  inline parent-task list; vault-wide `+` and `parent_replacement` need a Bob that
  emits the phase-one contract. An older Bob that sees bare
  `@route+block-id` as a missing-text sub-bullet reports `task text is required`, which
  the panel surfaces unchanged. An older Bob that does not emit `creates_pomodoro` still
  captures `@route:id#name` create-on-submit; the Mac app decodes a missing flag as false
  and simply omits the explicit Create row. An older Bob that omits `pomodoro_start`
  still previews and captures `@route:block-id` without a session; the Mac app
  decodes a missing start object as no session and shows no timer row, while a
  malformed `=<X>` suffix surfaces Bob's `invalid_pomodoro_start` diagnostic
  unchanged. An older Bob that omits `pomodoro_adjust` still parses `+5` as an
  ordinary task; the Mac app decodes a missing adjustment object as no
  adjustment and shows no adjustment row, while an invalid magnitude surfaces
  Bob's `invalid_pomodoro_adjustment` diagnostic unchanged. An older Bob that
  omits `pomodoro_shift` still parses `++3` as an ordinary task; the Mac app
  decodes a missing shift object as no shift and shows no shift row, while an
  invalid magnitude surfaces Bob's `invalid_pomodoro_shift` diagnostic
  unchanged. An older Bob that reports `=` as incomplete and `=3` as a task
  shows no start card or Start footer for whole-item starts; the panel simply
  previews that older behavior, so upgrade Bob before using `=`/`=<X>`. A start
  summary whose `tasks` array is absent still previews: the card shows the
  session with no queued rows. An older Bob that omits
  `pomodoro_close` has no close preview or Close footer; upgrade Bob before using
  `=x`. A close summary whose task, carried, notes, or next fields are absent
  still previews: booleans read as false, arrays as empty, and missing lines as
  zero, and unknown task roles degrade to a neutral row. A close summary whose
  `in_progress`, `park`, `complete`, `drop`, `task_links`, or `index` fields are absent
  still previews as today's unnumbered card: the spec decodes as no selection,
  rows decode as unnumbered, and no hint, summary, or badge renders. Whole-item
  `=x` (or the `=*`/`=!` aliases omitting `x`) reports `pomodoro_close` mode with a `pomodoro_close` span and a
  `{"raw": "=x"}` parse spec (`raw` preserves the exact alias, `=*` parks
  all numbered links and `=!` completes them); link items keep `pomodoro_link`/`pomodoro_task`
  mode with a `pomodoro_close` span kind over the suffix. A selection-bearing
  close adds `pomodoro_close_in_progress`, `pomodoro_close_park`,
  `pomodoro_close_complete`, and `pomodoro_close_drop` spans, an
  `in_progress`/`park`/`complete`/`drop` parse spec plus additive
  `park_all`/`complete_all` intent flags,
  and `task_links` plus per-row `index` in the capture summary; a dangling
  `,`/`~` reports mode `incomplete` with a `pomodoro_close_task` need and
  an `interactive_placeholder` span instead of an error. A present-but-empty
  `*`/`!` group selects all numbered links left after explicit assignments;
  explicit forms such as `=*1` and `=!1` narrow the action to task 1. Two
  empty wildcard groups compete and need numbers on at least one group. One
  entry may sit on the close line itself (`=x wired the lexer` logs to task 1
  for a plain close, or to the first eligible top-level worked link with
  wildcard intent; `=x1,3 3 fixed the flake` logs to task 3): an explicit number adds a
  `pomodoro_close_log_index` span in cyan on the close line while the default
  adds none, and a dangling inline number (`=x 2`) reports mode `incomplete`
  with a `pomodoro_close_log_text` need and an `interactive_placeholder`
  span over the number. Several entries use ⌃J bullets
  (`=x` plus `- 1 wired the lexer`, with `  - …` detail bullets under
  entries), which add a `log` parse spec with the typed entries in order,
  each carrying its `details`. Bullets may omit the number: unnumbered
  bullets log in order to the close's worked tasks (`=x3,4` plus `- foo bar`
  plus `- baz bam` writes exactly what `- 3 foo bar` plus `- 4 baz bam`
  writes), and a single worked task takes them all. Bullets are numbered
  all or none, and a leading number is always a task number (to log text
  that starts with a number, number every bullet). Numbered entries add
  `pomodoro_close_log_index` spans in cyan over each entry index while
  positional entries get no index chip; `capture-parse` omits `log[].index`
  for entries `bob capture` resolves against the running session, and the
  app decodes a missing index as nil. Entry and detail text keeps wikilink
  spans but is otherwise neutral prose, and a dangling bullet (`=x` plus
  `- 1`) reports mode `incomplete` with a `pomodoro_close_log_text` need
  and an `interactive_placeholder` span over the number instead of an
  error.
  Inline entries require a bob that understands them; an older bob reports
  `invalid_pomodoro_close` on the entry. An older Bob that omits `log` decodes as no typed
  entries, an older Bob that omits `details` decodes each entry without
  details, and an older Bob that omits `typed_work_log` or
  `typed_work_log_details` decodes as empty so the card shows only the capped
  `work_log` previews. A parked (`*<P>`)
  close records normal In Progress work without carrying those links forward;
  parked rows keep readable, unstruck, undimmed text with their actual
  transition, a `pause.circle` accent beside `Parked \u00b7 not carried`, and
  VoiceOver reading the task number, text, actual status, and
  "parked, not carried to the next Pomodoro". The summary uses `Continue`,
  `Parked`, `Complete`, `Deferred`, and `Dropped` groups in that order
  (for example `Continue 1 \u00b7 Parked 2, 3 \u00b7 Complete 4, 5`);
  `Continue` means ordinary worked links carried onward and never names a
  task status. `=x0*2` reports `Continue none \u00b7 Parked 2`. A dropped (`~<K>`)
  close removes those links from today without carrying or starting them; the
  card strikes and dims dropped rows, summarizes `Dropped 4, 5`, and reads
  "drops from today" for VoiceOver. A dropped row adds a "stays <status>"
  caption naming the lane the task keeps. The `=*`/`=!` and bare `=x*`/`=x!`
  all-task behavior requires the corresponding updated Bob executable. With an
  older Bob, the app displays that Bob's actual preview and submits the
  untouched draft through one Bob capture call; it never parses selection lists
  in Swift or simulates the new behavior. The app keeps
  schema-version rejection unchanged. A whole-item
  `=`/`=<X>` start reports the same numbered lineup: per-row `index` in the
  capture summary, a `drop` list on the parse spec and capture summary, and removed rows
  in `dropped` with their `index`, pre-image `ledger_line`, and `nested_lines`
  count; a trailing `~<K>` adds a `pomodoro_start_drop` span in the same muted gray as
  `pomodoro_close_drop`, and a dangling `~`/`,` reports mode `incomplete` with a
  `pomodoro_start_task` need and an `interactive_placeholder` span instead of an error.
  A start summary whose `drop`, `dropped`, `index`, or `nested_lines` fields are
  absent still previews as today's unnumbered card: the spec decodes as no drop, rows
  decode as unnumbered without badges, and no drop hint or summary renders.
  `toggle_direction` is `link` or `unlink` with `status_changed` on every
  result: linking shows the added link with `set Next`, `stays Next`, or
  `stays In Progress`, and unlinking shows the removed-link count with
  `stays <status>`. Older Bob builds that send `next`/`open` still decode to
  the same Set Next/Open footers. The app labels
  actions and notifications from Bob's returned behavior metadata, so a response
  that omits `toggle_behavior` still shows the two-way Set Next/Open footer,
  never Ensure Next. Captures that change today's `## Pomodoros` section also
  report a top-level `plan_budget` object with before/after theme and link
  meters, an `added_themes` list, and cap warnings that fire only while the
  batch grows a meter past its cap; the same destination carries a `role` of
  `current`, `next_up`, `named`, or `created`. With `plan.strict: true` a batch
  that creates a new named Pomodoro past the theme cap is refused atomically
  (exit 1, JSON `code: plan_theme_cap_exceeded`), and `pomodoro_name` create
  rows preview the resulting theme count with `plan_themes_after` and
  `plan_themes_cap`. An older Bob that omits `plan_budget`, `role`,
  `plan_themes_after`/`plan_themes_cap`, or `code` still previews and captures;
  the Mac app decodes each as absent and renders the destination row as
  `→ NAME`, omitting only the meter capsules, the cap badge, and the strict
  hint. A trailing `#now` tag is the ordinary trailing-tag error like any
  other `#tag`, and `#now` typed before the route is plain body text. The `^`
  active-task picker lists In Progress and Next tasks only. An older Bob that
  still sends the `now` flag, the `now_tag` span or completion context, or
  the `now` picker group still previews and captures; the Mac app decodes an
  unknown span as neutral, an unknown context as a generic row, and an
  unknown group as `note`.

The app never invokes a login shell to find `bob`. A Settings override must be an
absolute executable path.

## Development

```sh
just format-lint
just build
just test
just bundle
```

`just bundle` creates `.build/bundle/Bob Mac Capture.app` and signs it with the ad-hoc
identity `-`. Release installs should prefer an Apple Development identity:

```sh
just bundle "Apple Development: Name (TEAMID)"
just install ~/Applications "Apple Development: Name (TEAMID)"
```

`just install` is the complete update for the selected target: it restarts that installed
copy if it was already running, and leaves it stopped otherwise. See "Updating,
Reinstalling, and Rollback" below.

Ad-hoc signatures are useful for local development, but notification permissions and
launch-at-login trust are tied to the installed signed bundle. Reinstalling with a new
or expired certificate can require reauthorizing those system permissions.

## Runtime Contract

- Bundle identifier: `org.bobs.bob-mac-capture`.
- App type: `LSUIElement` resident menu-bar app.
- The `Bob` status-item menu offers Capture, Settings, Recheck Bob, Restart Bob Mac
  Capture, and Quit Bob Mac Capture, in that order. Restart discards an unsent draft;
  retained canceled drafts survive Restart and Quit. There is no confirmation dialog.
  Restart refuses to quit (reporting a failure instead) when the running process is not
  launched from an installed `.app` bundle or that bundle no longer exists on disk. See
  "Updating, Reinstalling, and Rollback" below for automatic install restart and the
  manual Restart item.
- Production hotkey (the default): Control-Shift-Command-I.
- Development/rollback hotkey: Control-Shift-Command-O, selectable in Settings.
- The hotkey path uses a pre-warmed non-activating `NSPanel`; subprocess work is kept
  off that path.
- A fresh popup is a compact, Spotlight-like bar — a one-line editor plus persistent
  footer actions, no empty preview placeholder, no dead space. Its first frame uses a
  conservative compact fallback only until SwiftUI reports rendered editor, auxiliary,
  and footer metrics. After that, the window's height tracks measured content as the
  editor grows with the draft, the completion list appears, the live preview arrives,
  and errors show or clear, staying anchored at the window's top edge. Measured
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
- `CaptureCore` imports only Foundation and runs `bob` directly through `Process` with
  argv arrays and an explicit GUI-safe environment.
- Editor highlighting is derived from `bob capture-parse --format json` spans. The app
  validates UTF-8 byte ranges and ignores a malformed span set instead of applying a
  partial grammar view. Every span kind — capture markers and the five Obsidian wikilink
  kinds (`wikilink_delimiter`, `wikilink_target`, `wikilink_heading`, `wikilink_block_id`,
  `wikilink_alias`) — resolves through the single palette in `CaptureEditorPalette`.
  The close-list spans `pomodoro_close_in_progress` and `pomodoro_close_complete`
  render orange and green, sharing the badge colors of the rows they select; the
  whole-item completion spans `task_complete_sigil` (green, the same complete-green
  as `=x!`), `task_complete_note` (route), and `task_complete_block_id` (block ID)
  reuse those existing colors, so the editor and the completion card never disagree
  about what a completion is;
  `pomodoro_close_drop` renders muted gray. The Work Log index span
  `pomodoro_close_log_index` renders cyan, sharing the tint of the typed entry
  line it lands on in the close card; it is not a completion span kind.
  Global destination spans (`global_route`, `global_sub_bullet_route`, and
  `global_sub_bullet_block_id`) reuse the existing destination and block-ID colors, so
  the editor and the completion list never disagree about what color represents what
  syntax.
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
  Block ID Picker instead (see below).
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
  Typing `^` as the whole capture item opens the Active Task Picker (`active_task`
  context), a modal mode of the capture panel — not a second window. Bob supplies one
  full snapshot (every In Progress and Next task with
  a block ID, in Bob's ledger order); the app filters that snapshot locally with
  a fuzzy matcher in `CaptureCore`
  so each keystroke is instant and flicker-free, and filter text never touches the
  draft. Local filtering is a deliberate presentation-only responsibility, the same
  precedent as the locally ranked `capture-targets` route cache. The picker opens when
  you edit the `route:block-id` part of a `^` item that is not already an exact
  candidate; a caret-only move shows a compact "Browse active tasks ⇥" chip instead,
  and Escape suppresses auto-open for that token while the chip offers a one-key
  reopen. Fast typing is safe: text typed before the picker appears seeds the filter.
  Return (or Tab, or a click) inserts exactly Bob's `route:block-id` into Bob's range
  and returns to the editor, keeping any typed `#name`/`=<X>`/`=x` suffix — the app
  never synthesizes that grammar, you type it after the insert. Command-Return inserts
  and captures in one step. An exact `route:block-id` never opens anything. When
  `capture-parse` reports `active_task` in `needs`, the app skips the doomed live dry
  run and shows "Pick an active task — press Tab to browse" instead of red
  incomplete-marker errors. Cached route completion never intercepts `^`, and the
  `active_task_route`/`active_task_block_id` spans reuse the route and block-ID
  highlight colors. The inline completion list is unchanged for every other context.
- While the Active Task Picker is open, printable keys edit the filter field natively
  (as do Cmd-A/C/V/X/Z, Ctrl-A/E, and Left/Right). Return/Tab inserts the selected
  task and returns to the editor; Command-Return inserts and captures;
  Shift/Option-Return and Shift-Tab are consumed. Down/Ctrl-N/Ctrl-J and Up/Ctrl-P/Ctrl-K
  move (wrapping); Page Up/Page Down move one page; Cmd-Up/Home and Cmd-Down/End jump
  to the first/last row. Escape clears a non-empty filter, then cancels (draft
  unchanged, caret restored, auto-open suppressed, chip shown). Backspace on an empty
  filter removes the `^` trigger and its fragment. Ctrl-S is consumed; Ctrl-C still
  stashes the draft and closes. While the chip is visible, Tab, Down, and Ctrl-N reopen
  the picker and Escape hides the chip.
### Task Link Picker

Typing `:` as the whole capture item opens the Task Link Picker (`task_link`
context), the same card as `^` with scope `:` and caption Open Tasks. When
`capture-parse` reports `task_link` in `needs`, the app skips the doomed live dry
run and shows "Pick any open task — press Tab to browse".

Bob lists every open (not done or canceled) task in area, project, and inbox
notes. With an empty filter tasks group in Bob's order: one section per queued
Pomodoro, then In Progress, Next, then one section per note
(`route.md` with its Inbox/Area/Project subtitle). The app filters locally with
spaces as AND terms; a non-empty filter replaces the groups with one ranked flat
list. Rows show a schedule capsule (`calendar` glyph) when Bob sends one and a
Pomodoro chip in the filtered view; the detail strip shows the insert action and,
when linking pulls a future schedule forward,
`Scheduled Oct 3 — linking pulls it forward`.

Return (or Tab) replaces the `:` query with `@route:block-id`; Shift-Return
inserts `@route:block-id=` so the live preview shows the start before Return
captures; Command-Return inserts then captures. Escape clears the filter, then
cancels to the reopen chip; Backspace on an empty filter removes the `:` token.

Tasks without an ID show `route:` plus a dim `plus.circle` suggestion; accepting
one opens the Add block ID prompt in link mode, prefilled with the first
suggestion (fully selected), with clickable suggestion chips and Tab / Shift-Tab
cycling, a live `Inserts @route:<typed>[=]` line, and buttons Add ID & Link /
Add ID & Start / Add ID & Capture. Return names the task via
`bob capture-task-id` then splices the link (appending `=` for Start, submitting
for Capture); failure keeps the prompt open with Bob's error; Escape returns to
the picker with the filter intact.

Bulk drafts work: each blank-line-separated item is judged alone.

Task Link Picker keys: Return/Tab Link, Shift-Return Link & Start,
Command-Return Link & Capture, Escape Clear/Cancel, Backspace on empty filter
removes `:`. In the link-mode Add block ID prompt, Tab / Shift-Tab cycle
suggestions.

### Parent Task Picker

Typing `@file+` opens the parent-task picker scoped to that note (`task` context
with Bob's additive `picker` descriptor, `scope: note`). Typing `+` at the start
of an otherwise empty item, or after a space at the end of a capture line, opens
the same card across capture notes (`task_parent`, `scope: vault`). Choosing a
task inserts `@file+id`. An older Bob that returns `task` without the descriptor
keeps the inline parent-task list.

The card uses the same picker lifecycle as `:` and `^`. Scope capsules read
`@cash+ · cash.md` or `+ · All capture notes`. Vault empty-query rows keep the
colon groups (queued Pomodoros, In Progress, Next, notes). Scoped empty-query
rows keep Bob's document order. A nonempty filter is one ranked list with spaces
as AND terms. Rows never show a Link & Start action or a schedule pull-forward
warning. The detail strip always says **Inserts @cash+goog-exit**.

When `capture-parse` reports `task_parent` in `needs`, the app skips the doomed
live dry run and shows "Choose a task to append to — press Tab to browse". A
lone whole-item `+` stays a valid +5m Pomodoro adjustment: the picker still
opens, Escape leaves the draft unchanged, and submitting it extends as before.
Bob lists `action_continuation_keys` (`0`–`9` and `+`) only for that dual-use
item. With an empty filter, an unmodified digit or second `+` closes the picker,
inserts that key once, and suppresses reopen so `+2` / `++3` match fast typing.
Scoped and prose-terminal pickers never use that handoff. A quiet footer hint
reads **Type a number or + to adjust; Esc to extend +5m**.

Return/Tab selects the task; Command-Return selects then captures;
Shift-Return is consumed and never appends `=`. Escape clears a nonempty filter,
then cancels to the reopen chip (**Select a parent task** / **Append to a
task**). Backspace on an empty filter uses Bob's `trigger_removal_range`: it
deletes a vault `+query` token, or removes scoped `+query` while leaving
`@route`. Exact identified `@cash+goog-exit` does not auto-open; Tab or the chip
still browses.

ID-less rows open Add block ID with suggestion cycling and a live
`Inserts @route+typed` line. Vault success requires Bob's `parent_replacement`;
if that field is absent the prompt stays open and asks to update Bob. Scoped
success inserts the returned ID into the ID-only range. Buttons read Add ID &
Select / Add ID & Capture.

Parent Task Picker keys: Return/Tab Select Task, Command-Return Select &
Capture, Escape Clear/Cancel, Backspace on empty filter removes Bob's trigger
range. In the card-mode Add block ID prompt, Tab / Shift-Tab cycle suggestions.

### Dependency Picker

Typing `&` at the start of an item or after whitespace opens the Dependency
Picker (`task_dependency` context), the same card with scope `&` and caption
Depends On. It consumes Bob's additive contract and never parses quoted note
components itself: Bob sends the decoded `query`, the lexical `owner`
(`new_task` / `existing_task`), the exact `note_path` (extension included, case
and Unicode preserved), the display `locator`, the `group`, `hidden`,
`already_dependency`, and `disabled_reason` per row, plus a Bob-authored
`replacement` (`&note:id`, quoted when the locator needs it) that is empty for
ID-less and guarded rows.

The header names the dependent (`For: @route+id`) or, for an ownerless leading
`&`, says Choose a prerequisite with "Then add task text or @note+id" —
choosing first stays allowed. With an empty filter rows group in Bob's order:
In Progress, Next, one section per note (`note_path`), then a separate
Completed history section (selecting there never blocks); `#hide` rows render
subdued and sort last within their section. A non-empty filter replaces the
groups with one ranked flat list. Already-added rows show Already added and
accepting one changes nothing; guarded rows carry Bob's explanation and neither
insert nor open the ID flow.

Return (or Tab) replaces only Bob's range with the replacement and returns to
the editor; at a terminal token one separating space is left for typing another
`&`. Command-Return inserts then captures only when the dependent is complete;
with no dependent yet it keeps the draft open ("Add task text or @note+id,
then capture"). Shift-Return has no start-session behavior on this source.
Escape restores the draft/caret and shows the Choose dependency chip; Backspace
on an empty filter removes the `&` token.

Rows without an ID show `locator:` plus a dim suggestion; accepting one opens
the Add block ID prompt ("Add ID and use task — edits that note now") in
dependency mode, calling `bob capture-task-id --note-path` with the exact path
(passing `--allow-closed` for Done/Cancelled history rows, which never
reopens them) and splicing Bob's `dependency_replacement` verbatim. Escape
returns to the picker with the filter intact; assignment failure inserts
nothing. The prompt buttons read Add ID & Use / Add ID & Capture.

### Complete Picker

Typing `!` at the start of an item opens the Complete picker
(`task_complete` context), the same card with scope `!` and caption
Complete. When `capture-parse` reports `task_complete` in `needs`, the app
skips the doomed live dry run and shows "Pick a task to complete — press Tab
to browse".

Bob lists every open task (Ready, Blocked, Next, In Progress) vault-wide,
today first. With an empty filter rows group in Bob's order: one section per
today Pomodoro (the running entry with the pink NOW pill, completed entries
recent-first with 🍅, their time range, and a Done capsule, queued entries
with UP NEXT), then "In today's note", In Progress, Next, and one section
per note (`note_path` with a `doc` icon). While filtering, two ranked
sections appear with their headers: Today then All open tasks. Rows show the
status glyph (Blocked is `pause.circle`), text, and locator (note in accent,
`:` , ID in indigo), a `🍅 N` capsule when the task was in two or more
Pomodoros today, and a schedule capsule when present. Disabled rows stay
visible with their reason badge and no insertion; recurring rows sort last.
The detail strip renders Bob's action line for the selected row
(`Inserts !sase:fix-flaky — completes it [*] → [x]`, with a Blocked variant
and the disabled reason).

Return (or Tab) inserts Bob's `!note:block-id`; Shift-Return inserts, appends
a blank line plus `!`, and the fresh picker opens with the just-picked task
marked "Already in this draft" for bulk completions; Command-Return inserts,
then captures. With an empty filter, Bob's continuation keys `!` and `[`
close the picker and type the key, so `!!` falls back to prose and `![`
hands off to embed completion. Escape and Backspace behave as in `:`.

ID-less rows open the Add block ID prompt via `capture-task-id --note-path`
and splice Bob's `complete_replacement` verbatim; Swift never builds the
token. The prompt previews `!<locator>:<id>` from Bob's candidate locator,
never the file name. The buttons read Add ID & Insert and Add ID & Complete.

Preview shows `New task · depends on …` or `Add dependency to "…"`, the
resulting `DEPENDS ON` child, the waiting count, and the Blocked/closed
distinction from Bob's `dependency_update`, reusing the final task-block
cards for target ID/status effects. A dependency-only action is never labeled
"Create task". The `&` editor text highlights through Bob's `dependency_sigil` /
`dependency_note` / `dependency_block_id` spans; Swift never regexes
ampersands. An older Bob does not understand `&`: the feature needs the
updated CLI (decoders stay backward compatible for every older payload).
- Typing the right-hand side of `@route:` or `@route^` anywhere those markers are
  valid opens the Block ID Picker (`pomodoro_block_id` / `task_block_id` contexts),
  and typing a trailing ` :` / ` ^` on a project-note bullet opens the Project task
  picker (`project_task_block_id` context),
  the same large, fuzzy, keyboard-first picker language as `^`, and never the inline
  list. Bob decides the intent and the app presents it: a marker-only `@route:` item
  gets a Link picker that browses the note's linkable tasks grouped by the note's own
  headings; every new-ID position (`@route^`, `@route:` on an item with text, either
  marker followed by the project-note `+`, or a project-task ` :` / ` ^` token) gets a New ID composer with Bob's
  suggestions from the task text, live availability against every ID already in the
  note, a one-key "next free" alternative when an ID is taken, and similar existing
  IDs for naming consistency. Bob supplies one snapshot (intent, candidates, every
  used ID with what uses it, suggestions, the marker token range, and the ID grammar
  as a one-character regex plus a human description); the app only filters locally,
  checks exact case-sensitive membership in Bob's used-ID list, applies Bob's
  character rule, and derives the `-2…-99` next-free variant validated by that rule.
  Live preview after insert remains the final authority. Opening rules mirror `^`:
  Link opens on edit unless the part already equals a candidate replacement (then
  nothing opens) or Escape suppressed auto-open (then the chip shows); New ID opens
  only when the part is empty or the caret is at the part's end, and any other edit
  shows the chip instead. A `task_block_id` response without a `block_id` object is
  treated as no completion. Link refetches the full snapshot at the range start when
  the caret is past it, exactly like `^`; New ID needs no refetch. Accept inserts the
  row's ID into Bob's range with the stale-draft guard, announces
  `Inserted @route:id`, and runs an `.edit` analysis without completion;
  Command-accept also captures, and a missing selection announces why instead of
  inserting. In the New ID composer the field only ever holds ID characters: typing a
  character outside Bob's allowed set (space, `#`, `=`, `+`, `.`, …) at the end of the
  field commits the typed ID and keeps typing that character in the editor, so `#`
  after a commit opens `pomodoro_name` completion naturally. The Link picker keeps
  `^`'s semantics: spaces separate fuzzy tokens. Backspace on an empty field deletes
  the `:`/`^` separator and the part so route completion resumes. The chip reads
  `Browse <note> tasks ⇥` (Link) or `Suggest an ID for <note> ⇥` (New ID); Tab, Down,
  and Ctrl-N open it and Escape hides it. When `capture-parse` reports `pomodoro_id`
  or `block_id` in `needs`, the app skips the doomed dry run with precedence
  `active_task`, then `pomodoro_id` ("Pick a task or type a new ID — press Tab to
  browse"), then `block_id` ("Type a new block ID — press Tab for suggestions").
  Older Bob binaries that send `pomodoro_block_id` without a `block_id` object get a
  Link picker without the New ID row and without type-through; older Bob never sends
  `task_block_id`, so `@route^` shows no picker there.
- Block ID Picker keys. Link matches the `^` table above; New ID adds Space.

  | Key                                        | Link                | New ID                          |
  | ------------------------------------------ | ------------------- | ------------------------------- |
  | Printables, Cmd-A/C/V/X/Z, Ctrl-A/E, ←/→  | Native filter edit  | Native edit; trailing illegal character commits the ID and keeps typing it in the editor (type-through) |
  | Return / keypad Enter, Tab                 | Insert selected row | Insert selected row             |
  | Command-Return                             | Insert, then capture| Insert, then capture            |
  | Shift/Option-Return                        | Consumed (`:` picker uses Shift-Return for Link & Start) | Consumed (`:` picker uses Shift-Return for Link & Start) |
  | Shift-Tab                                  | Consumed            | Consumed                        |
  | Down / Ctrl-N / Ctrl-J, Up / Ctrl-P / Ctrl-K | Move (wrap)       | Move (wrap), skipping status and info rows |
  | Page Up/Down, Home/End, Cmd-Up/Down        | Page / first / last | Page / first / last             |
  | Escape / Ctrl-[                            | Clear filter, else cancel (suppress, show chip) | Same |
  | Backspace on an empty field                | Delete `:` and part; route completion resumes | Delete `:`/`^` and part |
  | Ctrl-S                                     | Consumed            | Consumed                        |
  | Ctrl-C                                     | Stash and close     | Stash and close                 |
- The picker renders as one large elevated card spanning the full panel width: a
  46pt filter bar (a `^` scope token, the filter field, and a monospaced task
  count), a scrollable list with pinned Pomodoro headers, an 80pt detail strip,
  and key-hint chips in the footer (↑↓ Move · ↩ Insert · ⌘↩ Insert & Capture ·
  esc Clear/Cancel). The editor dims to 50% while picking; tapping it cancels.
  With an empty filter, tasks group by Pomodoro entry in Bob's order, each
  header showing its ordinal, name (or "Unnamed Pomodoro"), `HH:MM–HH:MM` time
  range when present, a pink NOW pill for the current entry, and a task count;
  unqueued In Progress and Next tasks follow under their own headers. A
  non-empty filter replaces the groups with one ranked flat list and a small
  pink Pomodoro chip per row. Rows are 34pt single lines: a status glyph
  (orange In Progress, blue Next), proportional text where `` `code` `` spans
  render monospaced on a faint fill and `[[wikilinks]]` render accent-tinted,
  fuzzy matches in semibold accent, and a trailing `route:block-id` locator in
  route/block-ID colors. The detail strip shows the full text (two lines), a
  metadata line (status, note label with its inbox/area/project icon,
  `› section`, Pomodoro wording), and `↩ inserts ^route:block-id`; after the
  first insert it also teaches `#name`, `=`, and `=x`. Empty states explain
  what a task needs to appear, Bob warnings collapse to one orange line
  (`+N more`), and a partial snapshot notes "Showing Bob's matches only". The
  panel grows once when the picker opens and never resizes while filtering; on
  short screens the card keeps a three-row minimum and scrolls. VoiceOver
  announces the open ("Active tasks, N tasks"), match-count changes, and each
  keyboard move; rows expose the full task label as a button, and selection
  and hover fills strengthen under Increase Contrast.
- The Block ID Picker reuses that card with per-mode anatomy. The scope token
  names the marker (`@sase:`, `@sase^`) with a Tasks, New ID, or Project note
  caption, plus `· line N` on multi-line drafts; a Project task session shows
  the bare ` :` / ` ^` sigil with a Linked task / Task ID caption and no
  `@route`. Placeholders read
  "Filter sase.md tasks, or type a new ID" (Link) and "Type a new ID for
  sase.md" (New ID). The trailing element is the count for Link ("96 tasks",
  "5 of 96") and a live availability badge capsule for New ID (green
  "Available", orange "Used · line 36", red with Bob's rule wording, secondary
  "113 IDs in use" while empty, "Checked on capture" for project notes), held
  to a fixed width range so the field never jumps while typing. Link groups
  rows under the note's own headings (`#` glyph in the section color, title,
  count; "Top of note" above the first heading); filtering replaces them with
  one ranked flat list that pins an exact block-ID match first and appends a
  trailing New ID row (or a Used status row) for a valid one-token filter.
  Link rows show the status glyph, rich text, a pink Pomodoro chip in filtered
  mode, depth indent, and a trailing `^block-id` locator. New ID rows show a
  green available ID, an orange taken status plus a "Next free" alternative, a
  red invalid status, an unchecked project-note row, accent `sparkles`
  suggestions with availability badges, and up to five dim 28pt "In use" info
  rows with fuzzy highlights (never selectable). Row locators use the session's
  own marker, so a `^` session reads `route^id` and a Project task row reads
  the bare `:id` / `^id`. The detail strip names the
  outcome per row kind — linked task, new task in `▣ sase.md` (or New Next
  task linked into today's Pomodoro, or the new project note, or for a Project
  task the Next task linked into today's Pomodoro / Task in `▣ cash_goog_exit.md`),
  plus `↩ inserts @sase:id` (`↩ inserts :draft-memo` for a Project task) — and
  after the first insert teaches `#name` or `=` (`:` IDs) or `+` for a project
  note (`+#name` picks its Pomodoro; `^` IDs), tracked separately per source.
  Project notes and Project tasks teach no follow-up.
  Empty states cover no linkable tasks, a missing note, no matches, and the
  empty composer. While any picker is open, the marker token being completed
  carries an accent wash in the dimmed editor (`marker_range` for block IDs,
  the `^` token included for `^`). Key hints match `^`; New ID adds
  `␣ Insert & keep typing`, and all hints fit the 620pt minimum width. Link
  budgets 4…11 grouped rows plus headers, New ID budgets a fixed 6; the panel
  grows once on open and never resizes while typing or filtering. VoiceOver
  labels read "Task picker for sase.md" / "New block ID for sase.md", opens
  announce "sase.md tasks, 96 tasks" / "New ID for sase.md, 3 suggestions",
  availability is announced only on category change, keyboard moves announce,
  and status/info rows are static text without the button trait. Fills
  strengthen under Increase Contrast and color is never the only signal:
  badges and rows carry text.
  Typing `#` immediately after a resolved `@route+block-id` follows the draft's mode:
  while that item has no body text it opens `pomodoro_name` completion for the task
  toggle, and once the item has body text it opens `task_section` completion for that
  task's ALL-CAPS section bullets. A standalone trailing `#` stays the Pomodoro-note
  marker and `@route#` stays note-section completion. Typing `#` immediately after a
  resolved `@route:block-id` — or a bare `@route:#` — opens `pomodoro_name` completion
  for today's open Pomodoros. Colon-Pomodoro (`@route:id#name`) selects or creates a
  named Pomodoro; plus-sub-bullet (`@route+id#section`) keeps its task-section selector
  as soon as body text exists. For
  blank-line-separated drafts, completion still sends the complete draft as one argv
  value; Bob scopes the answer to the item or declaration containing the UTF-8 cursor and
  returns replacement ranges in draft-global byte offsets. See "Wikilink Completion"
  below for the Obsidian-specific contract and row presentation.
- In the `@route+` and `@@route+` task contexts, Bob may return open tasks that still lack block IDs.
  Ready tasks stay first and insert in one action. Missing-ID rows replace the completion
  list with an inline **Add block ID** prompt; opening the prompt moves keyboard focus
  into the block-ID field so the ID can be typed immediately, with a highlighted field
  border while it holds focus. Canceling or completing the prompt returns focus to the
  capture editor. The draft remains unchanged while the app calls
  `bob capture-task-id --route ROUTE --task-ref REF --block-id ID --format json`.
  Only a confirmed Bob success splices the returned canonical ID into the saved
  replacement range and reruns preview. Cancel and every error keep the draft unchanged.
- In the `pomodoro_name` context, a matching named open Pomodoro stays the default and
  inserts its slug in one action. When Bob would create a new named future Pomodoro
  instead, the first row is an explicit **Create** / **New future Pomodoro** action
  (`creates_pomodoro: true`, canonical name, no ledger `ref`). Accepting it only
  canonicalizes the `@route:id#name` marker, closes completion without opening **Name
  Pomodoro**, restores the editor caret, and reruns live preview; the daily note is not
  mutated until the later `bob capture` transaction creates the placeholder and task
  link together. A create row that would push the plan past its theme cap
  (`plan_themes_after > plan_themes_cap`) carries a red `after/cap` badge
  (e.g. `4/3`). Unnamed and untypeable-name rows (`requires_name: true`, empty
  `replacement`) still replace the completion list with an inline **Name Pomodoro**
  prompt. The two prompts can never both be open. Opening the prompt pre-fills the name
  field from the in-progress completion query (`#deep-work` becomes `DEEP WORK`), moves
  keyboard focus into the name field, and shows a live `Saves as DEEP WORK` hint. The
  draft remains unchanged while the app calls
  `bob capture-pomodoro-name --pomodoro-ref REF --name NAME --format json`. Only a
  confirmed Bob success splices the returned canonical `slug` into the saved replacement
  range, restores the caret after it, and reruns analysis. Cancel and every error keep
  the draft unchanged. The create-future row never calls `capture-pomodoro-name`.
- In the `pomodoro_start_name` context — the name part of a whole-item
  `=<X>#name` named start, per token inside chains — the inline list is Bob's
  start-aware **Start** list: today's planned placeholders first (the entry a
  bare `=` would start carries `Next up` and a `Next` badge), then a **New
  session** create row for a missing name, then **Again** rows that start a
  new session named like a completed one (`Last ran 0830–0855`), then
  **Name it** rows for unnamed placeholders (which open the same **Name
  Pomodoro** prompt as `pomodoro_name`), and finally the already-running entry
  (`Running 0840–0905`), which can never be the default. Accepting a new row
  announces `NAME will be created and started when captured`; accepting an
  again row announces `Starts a new NAME session when captured`; both only
  splice the slug and the daily note is not mutated until the later `bob
  capture` transaction. The **New session** and **Again** rows carry the same
  red `after/cap` cap badge as the `pomodoro_name` create row when the new
  theme would push the plan past its cap. Typing `=#` opens the list
  immediately and shows the
  calm `Pick a Pomodoro to start, or type a new name` status instead of a
  doomed dry run; a caret on the `=<X>` suffix itself requests nothing. The
  list narrows as you type while the live preview already shows the resolved
  session, and Return starts it. An older Bob that reports no
  `pomodoro_start_name` context offers no rows there; the panel simply shows
  no completion until Bob is upgraded.
- Live preview calls `bob capture --dry-run --no-clip --format json -- <draft>` through
  a dedicated process-client API that asserts `--no-clip`. `%` markers stay literal in
  continuous preview; clipboard-resolving preview is a separate explicit action.
- The additive `sub_bullets` field on `capture` output is the exact rendered authored
  child lines, including Bob's target-selected indentation, and is omitted entirely when
  a draft has no authored bullets. `capture-parse` keeps `sub_bullets` as normalized
  bodies and adds aligned `sub_bullet_depths` values (`1` or `2`); missing depths from an
  older `bob` decode as depth `1`, and mismatched depths are ignored safely.
  `capture-parse` also decodes Bob's additive `items` array for batch drafts,
  preserving item index, source range, physical line range, route, section, needs, and
  authored-child depths. Its additive `global_destination` object is decoded
  tolerantly; absent metadata means the connected `bob` binary predates global
  destination declarations.
- `bob capture --format json` keeps the legacy top-level first result for a single
  capture or compatibility fallback, and may add an ordered `captures` array for a batch.
  The app normalizes both shapes to one collection before updating preview, status,
  VoiceOver announcements, notification content, and Command-Return opening; it keeps the
  additive top-level `global_destination` summary alongside that normalized collection
  and never splits a draft into multiple mutating `bob` subprocesses. When live preview
  reports exactly one `task_toggle`, the footer's primary action changes from
  **Capture** to **Set Next**, **Set Open**, or **Ensure Next** according to
  Bob's returned behavior metadata; when it reports exactly one `pomodoro_link`,
  the action becomes **Start** if the link starts a session and **Link** otherwise;
  a single close — whole-item `=x`, link `=x`, or new-task `=x` — becomes
  **Close**; a single whole-item `=`/`=<X>` start becomes **Start**; a single
  whole-item `!note:block-id` completion becomes **Complete**;
  batches keep **Capture** because Return will submit more than the toggle.
  Ensure Next preview, VoiceOver, and notifications present status and relocation
  independently ("Ready → Next" vs "Next unchanged", "Moved LATER → CURRENT" vs
  "Already in CURRENT; no Pomodoro changes") and never show the two-way "adds
  link" or "removed later links" rows. Committed notification titles summarize
  the actual result (combined, status-only, move-only, or already-Next no-op);
  Open Note/Open Notes includes the daily note only when `pomodoro_link_action`
  is `moved`. Pomodoro-link captures notify as `Started NAME`, `Linked to NAME`,
  `Moved to NAME`, or `Already in NAME`, batch lines use the link transition text
  under a `Link` kind, and Open Note/Open Notes includes the daily note whenever
  the link inserted, moved, or started a session. A Pomodoro close notifies as
  `Closed NAME` with a session-and-timing line, a tasks-and-Work-Log line (with a
  completed count when nonzero), and
  the next-session line; link and new-task closes use the same title and body,
  batch lines append ` (closed NAME)` under a `Close` kind, and Open Note
  targets the day file, which a close always writes. A project note that links
  tasks previews a link section ("Links 2 tasks into ADMIN (new)", one row per
  task with its text and `^id`), notifies "Linked 2 tasks into ADMIN", and
  includes the daily note in Open Note(s) whenever `task_links` is non-empty.
- Preview shows every block Bob will write, in Bob's own order: each item's parent
  `task_line`, authored children, then `clip.lines` and `schedule_log.lines` when the
  response carries them. Task-toggle items instead show the route/block destination, the
  status transition, the daily-note destination, and the `+` or `−` Pomodoro-link line
  Bob planned. Pomodoro-link items show the route/block destination, the status
  transition (`[ ] → [*]`, `[*] already Next`, `[/] stays In Progress`), the daily-note
  destination, and the ledger outcome Bob planned (`Linked under BUGS`,
  `Moved Task Link BUGS → FOCUS (created FOCUS)`, or
  `Task Link already in BUGS; no ledger change.`), plus the atomic-start session row
  when the link starts one. Every item with a `pomodoro_link_destination` also
  shows a destination row above it (`→ GOALS · next up`, `→ running GOALS 0945–1015`,
  `→ new Pomodoro BOB`, with a `timer` symbol) from the destination `role`, and a
  batch that changed today's Pomodoros section shows one plan-budget meter row above
  the items (`Themes 3/3`, `Links 8/10` capsules — green within the cap, red over —
  a `+1 BOB` delta chip whenever the themes meter grew, and orange warning captions).
  Both rows join the VoiceOver summary. A Pomodoro close instead shows its own card whenever
  `pomodoro_close` is present: a `stop.circle.fill` header with the `Close NAME`
  title and the monospaced session range (the shortened half tinted with the
  Pomodoro-session colour), the day-file destination plus a timing chip that is
  orange when early, green when on time, and secondary when over, a `link` via
  row for link closes (`Linked bob.md · ^ready into CAPTURE`, `Moved from SASE`)
  or a `plus.circle` row for new-task closes, up to six task rows with per-role
  glyphs, transitions (`[*] → [/]`, `[*] deferred`, `[x] closed`, `[x]`), text
  with strikethrough on struck rows, trailing locators, and Work Log previews —
  each row shows its `typed_work_log` entries first, all of them, with the date
  stripped, a `square.and.pencil` glyph in the cyan log tint, and primary text,
  each followed by its `typed_work_log_details` lines in secondary callout
  text, indented to the entry text with no glyph and never capped, followed by
  the remaining `work_log` entries in secondary text capped at two —
  then a notes row (`1 note stays`), a next-session footer row, and an
  empty state (`No Task Links — the session simply closes`) when there are no
  task rows. Numbered rows start with a fixed-width badge — a filled
  `N.circle.fill` when the row is listed, an open `N.circle` otherwise (monospaced
  digits in a capsule past 50), tinted orange for in progress, green for
  complete, and secondary for deferred, with unlisted rows dimmed so chosen rows
  stand out; unnumbered rows keep a clear spacer so text stays aligned, and with
  no numbered rows the card looks exactly like today's. Completed rows keep the
  embedded glyph tinted green with struck text and a `[*] → [x]` transition when
  the status changed. One caption row under the task rows teaches the syntax
  before a selection is typed (`=x1,2 keeps only these in progress · … · =x 2
  wrote the tests logs work to 2`, tinted like the editor spans, with the `2`
  in the cyan log tint) and shows the outcome summary after (`In progress 1, 3
  · Complete 2 · Deferred 4`, or `In progress none` for `=x0`); numbered rows
  never hide under `+N more`. The accessibility label includes the typed
  entries with their details after each entry. The footer's primary action becomes **Close**,
  the live-preview, preview, and submit status read `Would close …` / `Closed …`
  with started, completed (only when nonzero), and Work Log counts, and a failed
  dry run clears the card so no stale preview sits beside the error. The error
  callout shows Bob's message unchanged; a strict plan-budget refusal
  (`code == plan_theme_cap_exceeded`) adds the hint line `Queue it with ^ or
  defer with p:<N>.` While a
  list dangles on `,`/`!`/`~`, the card previews the trimmed draft dimmed with a
  `Type a task number after ,` row, **Close** is disabled, and Return cannot
  submit; while a Work Log bullet dangles (`=x` plus `- 1`), the card previews
  the rest dimmed with a `Type the Work Log entry for task 1` row, **Close**
  stays disabled, and Return cannot submit; a valid draft
  restores the normal card. While a start list dangles on
  `~`/`,`, the start card previews the trimmed draft dimmed the same way with
  **Start** disabled instead. A whole-item `=`/`=<X>` start instead shows its own card
  whenever `kind` is `pomodoro_start`: a `play.circle.fill` header with the
  `Start NAME` title and the monospaced session range, the day-file destination,
  then one caption row — the teaching hint before a drop is typed, the drop
  summary after (`Dropped 2, 4`, plus ` · nothing left queued` when nothing stays
  queued), or the pending notice while a list dangles — followed by the queued-task
  rows merged with dropped rows in lineup order. Each numbered row gets the close
  card's number badge (`n.circle`, filled for dropped rows, capsule above 50) with
  status glyphs (`circle` Ready, `circle.inset.filled` Next,
  `circle.lefthalf.filled` In Progress, `questionmark.circle` other,
  `minus.circle` dropped, `exclamationmark.triangle` unresolved with the warning
  as help text), task text with a truncating `note ^id` locator; dropped rows
  render struck and dimmed with a
  caption joining `stays <status>` and `with N nested line(s)`. Numbered rows never
  hide under `+N more`; rows without numbers (older Bob) render exactly like
  today's card. A created session shows a
  small pink **New** capsule next to the title on a dry run (**Created** once
  committed, and the notification reads `Started NAME` with `0905–0930 (25m)
  · New session`); with no drop typed and a non-empty lineup, a bare `=`/`=<X>`
  start teaches `Type ~2 to drop task 2 · #name to start a specific Pomodoro`
  (`Type ~1 to drop it · …` for one row), with `~N` tinted like the drop span and
  `#name` like the editor's name span, while a named start teaches only the drop
  half. An empty lineup keeps the quiet `Type #name to start a specific Pomodoro`
  caption, and named starts with an empty lineup show no hint. Dropped rows read
  "Task 2, …, drops from today" and queued rows "Task 1, …, queued" for VoiceOver.
  A still-running error keeps the red error block with Bob's one-line-switch
  message unchanged. The footer's primary action
  becomes **Start**, the live-preview, preview, and submit status read
  `Would start …` / `Started …` with the session and line (plus ` · drops 2` /
  ` · dropped 2` once a drop is typed), and the notification
  reads `Started NAME` with the session and queued-task count (counting `tasks`
  only, plus ` · dropped 2`). One item stays compact; a batch renders an ordered stack with item count,
  destination/kind metadata, dividers, and exact `previewBlockLines` or toggle
  transition rows. When Bob reports a global destination, preview and the destination
  detail show one compact shared-scope line (`All items → foo.md` or
  `All items → foo.md · under ^a-id`) and mark item-level deviations as local overrides
  instead of repeating the shared target on every item. The outer auxiliary detail region
  owns scrolling, so preview itself never nests another scroll view. The preview card
  always takes its natural height: the window grows to show it in full up to the screen
  limit before the auxiliary region scrolls, and the card keeps its last rendered height
  while a live preview reloads. Continuous live
  preview passes `--no-clip`, so it has no `clip` to show; the explicit **Preview**
  button and **Capture** resolve the clipboard and therefore mirror the full block.
  Whenever Bob reports batch-level `pomodoro_blocks`, every Pomodoro the capture
  touches, creates, or reports renders once below the item stack as a full block view:
  a status caption (`Running · line 27` with a `play.circle.fill` glyph, `Completed`
  with `checkmark.circle.fill`, `Queued` with `circle.dashed`) plus a pink **New**
  capsule on a dry run (**Created** once committed), then a card with a status rail,
  a diff gutter (`+` green for added lines, `•` accent for changed lines with the old
  text on hover, `−` red for removed lines), indent guides per depth, and the verbatim
  lines Bob will write — tinted like the editor (pink time range, wikilink colors,
  checkbox colors) with no truncation. Standard items whose verbatim lines the blocks
  already cover omit the duplicated stack, and the blocks dim to 0.6 together with the
  close card while a close-list selection dangles. An older Bob that omits
  `pomodoro_blocks` previews exactly as before. `PomodoroBlockDesignTests` renders the
  adjust, close, link-move, created-named-start, and chain fixtures to PNG
  (light/dark, 760/620 pt, scale 2) when `BOB_MAC_CAPTURE_RENDER_DIR` is set.
  Whenever Bob reports batch-level `task_blocks`, every parent task a sub-bullet
  capture wrote under renders once below the item stack as a full task card, before the
  Pomodoro blocks: a picker-status caption (`In Progress · sase.md · line 1` with the
  `@+` chooser glyph and color) plus a pink **New** capsule on a dry run (**Created**
  once committed), then the shared diff card with task tinting (tertiary list markers,
  checkbox colors, secondary `#tags` and `[key:: value]` fields, indigo trailing
  `^block-id`, wikilink colors, semibold task-line prose) and no truncation. Covered
  sub-bullet items switch to a compact `↳ Sub-bullet under ^id` header (with
  ` › SECTION` when Bob reports one) and drop the verbatim stack and trailing note
  line; uncovered items render exactly as before. Blocks above 24 rows fold quiet runs
  of 4 or more unchanged rows into `⋯ N unchanged lines` rows that expand on click
  (with a **Show all lines** action); smaller blocks never fold. A single sub-bullet
  names its parent in the status and summary (`Preview → sase.md › ^id`), and an older
  Bob without `task_blocks` previews exactly as before. `TaskBlockDesignTests` renders
  every task-block fixture to PNG (light/dark, 760/620 pt, scale 2) when
  `BOB_MAC_CAPTURE_RENDER_DIR` is set.
- The preview path assigns a fixed `BOB_PRIORITY_ROLL_SEED` for the draft lifecycle so
  randomized `p:<N>` scheduled dates can be reused by submission. Bob derives
  item-specific rolls from that seed for batch drafts, and the seed resets only after a
  successful capture or discard.
- Capture targets are cached at launch, refreshed when the panel opens, and invalidated
  by a coalesced FSEvents watcher. Watcher or refresh failures mark the cache stale
  without clearing the last good route list.
- Every `bob` invocation is bounded by a 20-second timeout (`BobProcessClient.defaultTimeout`)
  that terminates and reaps a wedged process instead of leaving the panel waiting
  indefinitely; a fired timeout surfaces as an actionable `BobClientError.timedOut`. Quit
  cancels every outstanding invocation via `cancelActiveProcess()`.
- A successful aggregate capture hides the panel automatically only after Bob returns
  success for the whole draft; a failed capture keeps the panel open with its complete
  draft and an actionable error. Command-Return opens every unique returned target in
  source order. Reopening the panel after a success starts from a clean slate — the prior
  "Captured → …" summary and status text are cleared, while a retained draft (from Escape
  or a failure) reopens exactly as it was left. Closing the panel never destroys a draft.
  **Discard** permanently clears the draft, while Control-C stashes a semantically
  nonempty draft before clearing and closing.
- Canceled drafts persist across Quit, Restart, crash, and logout in
  `~/Library/Application Support/org.bobs.bob-mac-capture/canceled-draft-stash.json`
  (`schemaVersion` 1, newest-first array order). The directory is mode 0700 and the file
  is mode 0600. Settings persists only the capacity (in `UserDefaults`), defaults it to
  10, and clamps it to 0...36. Zero turns the feature off and deletes the file. Capacity
  reductions keep the newest entries and drop older overflow. Repeated cancellations are
  retained as separate entries, even when their text is identical. Settings also shows
  the retained count and a confirmed **Clear Stash...** action, which deletes the file.

### Completing tasks with `!`

A capture item that is exactly `!note:block-id` completes that existing open task
without closing a Pomodoro: the task line closes exactly as `=x!N` would write it,
its Task Links retire in today's ledger the way `bob task reconcile` would retire
them, and Blocked dependents recover the way Ctrl+Enter recovers them. Bulk works
one `!` item per blank-line-separated block; any failure rolls the whole batch back.

The completion preview card shows the struck task (`[*] → [x]` with Bob's clean
task text struck and dimmed), one row per closed embedded subtask, one row per
descendant left open, the ledger effect named per entry (`Strikes/Struck its Task
Link in CAPTURE`, with ` (completed)` for completed entries,
`Moves/Moved its Task Link SASE → CAPTURE, struck`,
`Task Link already in PLAN; drops/dropped the SASE copy`,
`removes/removed empty SASE`), and one row per unblocked dependent — with
`list.bullet.indent`, `timer`, and `lock.open.fill` fact rows under
a green `checkmark.circle.fill` seal (`Already done — nothing to change` in gray for
the idempotent no-op). An older Bob without `text`, `struck_in`, or `dropped` keeps
the count-based ledger wording and the local task-line text. The footer action is
**Complete** and every fact joins the VoiceOver summary. Notifications read
`Completed: <task>` (`Completed N tasks` for an all-completion batch) with
`sase.md · unblocked <name>` bodies, and Open Note(s)
includes the daily note whenever the ledger changed. An older Bob without
`task_complete` decodes as no completion preview and keeps the standard card; upgrade
Bob before using `!`.

## Keyboard

| Key | In the editor | While completion is visible | While Add block ID is open | While Name Pomodoro is open |
| --- | --- | --- | --- | --- |
| Return | Capture, then close the panel | Accept the selected completion | Add the ID and select the task | Name the Pomodoro and select it |
| Command-Return | Capture, open the target in Obsidian, then close the panel | Accept, then submit | Consume the key; do not capture | Consume the key; do not capture |
| Shift-Return / Option-Return | Insert a newline | Insert a newline | Add the ID and select the task | Name the Pomodoro and select it |
| Ctrl-J | Insert a new indentation-aware `- ` row; anywhere before a populated dash bullet's body, remove the prefix into a blank separator and keep its body | Same edit, and close completion | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-O | Insert a blank physical line immediately above the current line and move the caret onto it | Same edit, and close completion | Native text-field behavior | Native text-field behavior |
| Ctrl-U | Delete from the caret to the beginning of the current physical line; when the caret is already at that start, delete the previous line instead, stopping on the first line | Same deletion, closing completion | Native text-field behavior | Native text-field behavior |
| Ctrl-A | Move to the beginning of the current physical line; when the caret is already there, move to the beginning of the previous line, stopping on the first line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Ctrl-E | Move to the end of the current physical line; when the caret is already there, move to the end of the next line, stopping on the last line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-J | Move the caret to the next physical line, keeping the current column when that line is long enough and clamping to its end when it is not; stops on the last line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-K | Move the caret to the previous physical line, keeping the current column when that line is long enough and clamping to its end when it is not; stops on the first line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Command-V | Insert the clipboard's plain text, discarding source formatting; when an empty bullet row receives a Markdown bullet list, consume the first pasted marker and align the list to that row | Same paste edit, and close completion | Native text-field paste | Native text-field paste |
| Backspace | Remove an unused `- ` row in one action (native Backspace everywhere else, and for every modified Backspace) | Remove an unused `- ` row in one action | Native text-field Backspace | Native text-field Backspace |
| + | Insert `+` | While route completion is visible, directly after the route being completed: accept the selected route, keep the `+`, and open task completion | Native text-field behavior | Native text-field behavior |
| Tab | Expand an immediately preceding `--` to `—`; otherwise indent the current column-zero continuation bullet to two spaces (normal focus traversal if neither applies) | Accept the selected completion | In link mode cycle suggestions; in the `@route+` prompt consume the key | Consume the key; do not expand, indent, or capture |
| Shift-Tab | Outdent the current two-space continuation bullet to column zero (normal reverse focus traversal otherwise) | Same outdent, then close completion | In link mode cycle suggestions backward; in the `@route+` prompt consume the key | Consume the key; do not outdent or capture |
| Down / Ctrl-N | (normal focus traversal) | Select the next completion | Consume the key; do not move completion selection | Consume the key; do not move completion selection |
| Up / Ctrl-P | (normal focus traversal) | Select the previous completion | Consume the key; do not move completion selection | Consume the key; do not move completion selection |
| Escape / Ctrl-[ | Close the panel, retaining a nonempty draft without confirmation | Close completion | Cancel back to the task list | Cancel back to the Pomodoro list |
| Control-S | Open the canceled-draft stash picker | Open the canceled-draft stash picker | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Control-C | Stash a nonempty draft, then clear and close | Stash a nonempty draft, then clear and close | Stash a nonempty draft, then clear and close | Stash a nonempty draft, then clear and close |

Every capture action is reachable from the keyboard alone; the hotkey, editor, completion
list, Stash/Capture/Preview/Discard buttons, and stash picker never require a pointer.
Opening the **Add block ID** or **Name Pomodoro** prompt moves keyboard focus into that
prompt's field; that field's first responder is owned directly by AppKit rather than
SwiftUI focus, and a keystroke arriving while nothing holds focus re-claims the field.
Canceling or completing the prompt restores focus to the capture editor. The editor starts at one
visual line and grows and shrinks with rendered content up to a screen-derived budget,
then scrolls internally for longer drafts.

The footer's **Stash** action shows the number of retained canceled drafts and matches
Control-S. If the stash is empty, opening it reports "No canceled drafts yet" without
logging draft text. If the editor currently contains any characters, the picker refuses
to open; capture, retain, cancel, or explicitly discard the live draft first so restore
can never overwrite work. **Discard** is intentionally different from Control-C: it is a
permanent discard and never adds an entry to the stash. Control-C on an empty or
whitespace-only editor closes without adding an entry.

While the stash picker is open, it is modal inside the panel's auxiliary region and
uses the same compact material style as completion. Rows are newest first. Restoring a
row installs that exact text in the empty editor with the caret at the UTF-8 end, removes
only that restored entry from the stash, keeps the panel open, and starts normal
parse/live-preview analysis. This is a pop operation: non-restored entries remain in
order. Pressing uppercase `D` with Shift-D or Caps Lock, or clicking
**Shift-D Delete All**, immediately clears every retained canceled draft permanently,
including the on-disk file, closes the picker, leaves the panel open with an empty
editor, and reports only "Canceled draft stash cleared". Lowercase `d` does nothing
destructive. The Settings **Clear Stash...** action keeps its confirmation dialog for
that non-modal workflow.

| Key while stash is open | Behavior |
| --- | --- |
| 1...9, 0, A...C, -, E...Z | Restore that row immediately |
| Shift-D | Delete all retained canceled drafts |
| Return | Restore the selected row |
| Down / Ctrl-N | Select the next row, wrapping at the end |
| Up / Ctrl-P | Select the previous row, wrapping at the top |
| Escape / Ctrl-[ | Close only the stash picker |
| Control-S | Close the stash picker |

The 36-entry upper bound exists so every retained row always has a unique one-key
accelerator while reserving `D` for Delete All: `1` through `9`, then `0`, then `A`
through `C`, `-`, and `E` through `Z`.

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
`s:<N>`, `p:<N>`, `%`, …) at the end of any valid line configures that item even
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
- Attach the final checklist @work p:1
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
`@route:block-id` keeps the Pomodoro-linked next-task behavior, `@route:block-id#name`
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
and the notification summarizes the same returned start. Type `=x`, a blank
line, then `=` to close the running session and start the next one in a single
draft. A whole-item `=x` closes
the running Pomodoro; `@route:block-id=x` links an existing task first, and
`<text> @route:block-id=x` creates a task inside that session before closing it.
Appending task numbers chooses each Task Link's outcome: `=x2` keeps only 2 in
progress, `=x!2` completes 2, `=x1!2` does both, and `=x0` defers all (single-quote
the argument in zsh, since `=` and `!` expand). The same suffix works on link
forms. Work Log bullets log while closing: type `=x`, then `⌃J` for a `- ` bullet,
then either `1 wired the lexer` to add `wired the lexer` under link 1, or just
`wired the lexer` to let Bob file it by position — unnumbered bullets log in
order to the close's worked tasks, and a single worked task takes them all —
before the unchanged close writes it to that task's Work Log; `⌃J` then `Tab`
nests a `  - …` detail under the entry, `⌃J` then `⇧Tab` starts the next entry,
and `⌫` on a bare `- ` row deletes it. Bullets are numbered all or none, and
a leading number is always a task number, so `- 1 fixed 3 bugs` needs no escape
(to log text that starts with a number, number every bullet). Numbered entries
get a cyan index chip matching the card's new entry line, while positional
entries get none. Text on the `=x` line itself still takes an inline entry
(`=x wired the lexer` logs to task 1): it shows the bullet to write instead. A trailing `~<K>` drop list on a whole-item start (`=~2`, `=3~2,4`,
`=#bugs~2`) starts the next session without those numbered queued Task Links —
`~` drops, so `=~2` drops task 2 from the session you start the way `=x~2` drops
task 2 from the session you stop, using the numbers the start card shows. The
start card numbers every queued row, strikes and dims dropped rows in place with
a `Dropped 2` summary, and teaches `Type ~2 to drop task 2` until a drop is typed.
The
dedicated close preview shows Bob's session timing, task transitions, Work Log entries
with their details, and next session. The footer says **Close**, and the notification summarizes the same
returned close. Missing or ambiguous running sessions surface Bob's error in the
preview. A list left dangling on `,`/`!`/`~` is an editing state, not an error: the
card stays live on what is typed so far with **Close** disabled until a task
number follows; a dangling Work Log bullet (`=x` plus `- 1`) previews the rest
dimmed with `Type the Work Log entry for task 1` and keeps
**Close** disabled; a start list left dangling on `~`/`,` previews the trimmed start
the same way with **Start** disabled instead. A marker-only `@route+block-id` ensures that existing task is Next and
relocates its Task Link, `@route+block-id#pomodoro` does the
same onto a named Pomodoro (creating the named future Pomodoro if needed),
`@route+block-id!` is the explicit link-presence toggle: it links an unlinked
task (Ready and Blocked rise to Next, Next and In Progress keep their lane)
and unlinks a linked task without touching the lane, and `@route+block-id` with
body text nests beneath the task. `@route+block-id#section` nests under that task's
matching section bullet once body text is present; the same `#` position opens the
Pomodoro-name popup while the item is still marker-only, including the
create-future-Pomodoro row and **Name Pomodoro** prompt. The app labels Ensure Next
versus Set Next/Open from Bob's returned `toggle_behavior`, never by parsing `#` or `!`. The `@route+` parent-task picker (and the vault-wide `+` picker) plus Add block ID prompt are still how a task
without a block ID becomes selectable. The app does not duplicate those grammar rules; it
colors the span kinds Bob reports, asks Bob for completion at the real caret, and
submits the original draft text.

Ctrl-J starts the next canonical `- ` row from anywhere in the draft, copying exactly the
current authored row's supported indentation (zero or two ASCII spaces). With a
collapsed caret at column zero, inside leading whitespace, on either side of the hyphen,
after the `- ` prefix, or anywhere through the first body character of a populated `- `
row, Ctrl-J replaces that row's leading whitespace and `- ` prefix with one line
terminator while preserving the body. For example, `Parent\n|- child` and
`Parent\n- |child` both become `Parent\n\n|child`. Only a caret inside or after the body
keeps the normal new-row insertion behavior. On a line that
contains only optional whitespace plus one `-`, `*`, or `+` marker, Ctrl-J replaces the
placeholder with exactly one blank item separator and puts the caret at the beginning of
the following line, reusing an existing line terminator when one is already there.
macOS smart-dash substitution is disabled in the draft editor so `--3` and `-2`
stay literal ASCII hyphens; smart quotes are unchanged. Plain Tab first checks
for a local editor snippet: with a collapsed caret immediately after `--`, it
replaces those two ASCII hyphens with a single em dash `—` and leaves the caret
right after it, everywhere else in the editor including inside prose. To submit
a one-unit earlier shift, type `--` and press Return without pressing Tab first.
Only when no snippet matches does Tab fall through to bullet indentation. To
author a nested row,
press Ctrl-J from an existing nested row, or press Ctrl-J for a fresh top-level
placeholder and then Tab before or after typing its body to indent it under the preceding
first-level bullet. Shift-Tab reverses that, returning a nested bullet to column zero.
Tab/Shift-Tab only move a continuation bullet between Bob's two supported source
prefixes, exactly two ASCII spaces, so pasted or hand-authored drafts must still use that
exact two-space indent; they stop at that ceiling and floor and leave every other line
untouched. Ctrl-U deletes from the caret to the beginning of the current physical line,
and when the caret is already at that start -- where there is nothing left to delete --
it removes the previous line entirely, so repeated presses walk up the draft line by line
and stop on the first line.
Backspace on an empty `- ` row removes it in one action instead of requiring two ordinary
backspaces. All five shortcuts act on the native text view directly, so undo, IME
composition, and accessibility behave exactly as they do for any other edit, and Bob's
live parse/preview remains the sole authority for whether the resulting hierarchy is
contextually valid. Ctrl-A and Ctrl-E move the caret to the beginning and end of the
current physical line, and when the caret is already on that edge they step to the
beginning of the previous line or the end of the next one, so repeated presses walk the
draft line by line. They stop at the first and last line rather than wrapping around, and
because they only move the caret they never touch the draft's text, undo history, or an
in-flight IME composition.

Ctrl-Shift-J and Ctrl-Shift-K move the caret to the next and previous physical line,
keeping the column it started from: passing through a shorter line clamps the caret
to that line's end, and the next press in the same direction restores the original
column on the first line long enough to hold it. Any other keystroke, click, or edit
resets that remembered column. They stop at the last and first line rather than
wrapping around, and like Ctrl-A and Ctrl-E they only move the caret, so they never
touch the draft's text, undo history, or an in-flight IME composition. Exact Ctrl-K
is again left to AppKit's native delete-to-end-of-paragraph binding, while
Ctrl-Shift-K is the custom upward move and Ctrl-U remains Bob's custom line-deleting
shortcut.

Command-V intentionally reads only the clipboard's plain-text flavor. Source formatting
is discarded because Bob's capture grammar is plain text, and letting AppKit choose a
rich HTML/RTF flavor forced a synchronous WebKit HTML import that could cost seconds per
paste from browser content. When the caret is at the end of an otherwise empty `- `,
`* `, or `+ ` row and the clipboard begins with a Markdown `-`, `*`, or `+` bullet with
a body, Command-V treats that row as the first pasted bullet: the row's marker is kept,
the clipboard's first marker is consumed, and the remaining pasted lines are rebased to
the row's column-zero or two-space indentation.

```text
Plan rollout
-
```

Pasting:

```text
- Confirm owner
- Attach checklist
```

Produces:

```text
Plan rollout
- Confirm owner
- Attach checklist
```

Every other clipboard shape, selection, caret position, and unsupported indentation
still follows ordinary plain-text insertion.

## Wikilink Completion

Typing an Obsidian wikilink anywhere in the draft — a note (`[[sas`), an embed
(`![[sas`), an alias (`[[Artificial Intelligence|AI`), a heading (`[[sase#Des` or the
same-note `[[#Des`), or a block reference (`[[sase#^goog` or the same-note `[[#^goog`) —
drives completion the same way capture-marker syntax does, keyed off the real caret
position rather than the end of the draft. `bob-cli` owns every part of this: vault
discovery, ranking, and the exact replacement text and byte range; the app only
decodes and presents it.

- **Note completion** (`wikilink_note`) inserts a vault-relative path without `.md`
  (`[[sase]]`), or the canonical `[[path|Alias]]` form when the match came from a
  frontmatter alias — never a bare alias with no path.
- **Heading completion** (`wikilink_heading`) resolves against the capture's own
  destination for `[[#...]]`, a named note for `[[Note#...]]`, or the whole vault for
  `[[##...]]`.
- **Block completion** (`wikilink_block`) works the same way for `[[#^...]]`,
  `[[Note#^...]]`, and vault-wide `[[^^...]]`.
- Accepting a candidate always applies the server's exact byte range and `cursor_after`
  in one step, so the caret lands exactly where typing would have left it — after the
  closing `]]`, mid-heading, or wherever the candidate specifies.

Each completion row shows a compact SF Symbol and context label for what will be
inserted (Note/Heading/Block, alongside Destination/Section/Parent Task/Task Section
rows), a primary line with restrained emphasis on the part of the text
that matched what you typed, and a secondary line with the canonical vault-relative
path, parent task, or `route:block-id` plus small badges — `Alias`, a heading level
like `H2`, a short block preview, `^block-id`, `Add ID`, `N items`, or `Empty`.
`^` active tasks no longer use this list; they open the Active Task Picker above.
`@route+` task suggestions are grouped as
**Ready to use** followed by **Needs block ID**, preserving Bob's order inside each
group; task-section rows stay a plain ungrouped list. Long paths truncate from the
middle, keeping the filename intact rather than the leading directory. The selected
row's accent-tinted fill uses each result's own semantic color (matching the editor's
highlight palette) and increases its opacity automatically under Increase Contrast.
VoiceOver announces the context, the count of results, and each row's full
context/name/path/badge description before "double-tap to insert."

Note metadata — paths, stems, frontmatter aliases, heading text, and block-id previews
— is read directly by `bob` from the local vault to build these candidates. The app
never logs it, writes it to `UserDefaults`, or includes it in a notification, signpost,
or Diagnostics entry; see Privacy below.

## Live Preview and Clipboard Semantics

The continuously updated preview below the editor calls
`bob capture --dry-run --no-clip --format json` on every debounced edit and never reads
the clipboard, so `%`, `%N`, and `%header` markers stay literal while you type. Pressing
the explicit **Preview** button or **Capture** resolves the clipboard and Clipy history
normally, exactly as the final capture would. A `p:<N>` random schedule is rolled once per
draft and reused by every subsequent live preview and by the final submission, so the
displayed scheduled date always matches what gets written.

## Notifications

The app posts success and failure `UNUserNotificationCenter` notifications and never
makes capture correctness depend on them. Success notifications use Bob's semantic
capture text rather than raw draft syntax: a single capture is titled `Task captured` or
`Note captured`, names the destination, and includes scheduled-date metadata when Bob
returns it. A close is titled `Closed NAME` and its body carries the session and
timing line, the tasks and Work Log line, and the next-session line. A batch is titled with the item count, summarizes task/note and destination
counts, and emits one ordered body line per captured item without substituting an
ellipsis for later entries. Close batch lines append ` (closed NAME)` and count
under a `Close` kind. When Bob reports a global destination, a same-scope batch
uses compact wording such as `2 tasks · foo.md` or `2 notes · file.md · under ^a-id`;
only items that locally override the global declaration repeat their actual destination.
The raw `@@...` declaration is never included in notification text. The only newly
authorized notification body content is the captured semantic text; failure
notifications still carry only the bounded error message. The install-complete banner
uses fixed copy with no path, identity, version, or capture text.

Capture notifications register singular and plural foreground actions (`Open Note` and
`Open Notes`). The notification stores the legacy first `targetPath` plus an ordered
`targetPaths` array, and clicking the notification or pressing its open action routes
every unique Obsidian destination in source order. If Bob returns no usable destination,
the notification remains informative and omits the open action. Settings shows live
authorization status, a button to request authorization, a link to the system
notification settings pane, and a test-notification action.

Notification delivery and authorization persistence require the installed, signed
`Bob Mac Capture.app` bundle (`just bundle` + `just install`), not `swift run` or a raw
`.build` binary: macOS ties notification permission grants to a stable bundle identity
and code signature, and Settings reports the current signing state under Diagnostics.

When `just install` restarts a copy that was already running, the replacement process
posts one native completion notification after it finishes launching:

- title: `Install complete`
- body: `Bob Mac Capture restarted successfully.`
- sound: the default notification sound
- action: `Capture`

Clicking the banner or choosing `Capture` opens the capture panel; dismissing it does
nothing. The banner is confirmation that the replacement process itself reached a usable
launch point, not that the install helper merely asked LaunchServices to open the bundle.
It is requested only for that one-shot install-triggered restart, and only when macOS
already allows notifications for the signed bundle. An install never prompts for
notification permission. Denied or not-yet-requested authorization is silent and
non-fatal: the replacement still launches. A stopped install does not launch the app and
does not notify. `Bob → Restart Bob Mac Capture` is a manual relaunch, not an install
completion, and does not show this banner.

## Hotkey Conflicts and Launch at Login

If `RegisterEventHotKey` fails — most often because another app already owns the
configured shortcut — the app does not silently do nothing. Settings' Diagnostics
section reports "Hotkey conflict" with the underlying Carbon status, and the same event
is recorded in Recent Activity. Use "Recheck Bob" from the menu-bar item after freeing
the shortcut, or use Settings to switch between the production and rollback bindings.
New installs default to Control-Shift-Command-I; turn off **Use production
Control-Shift-Command-I** only when restoring the retired Hammerspoon capture workflow.

Launch at login is controlled from Settings via `SMAppService.mainApp`. If macOS reports
"Requires approval in System Settings," open System Settings → General → Login Items and
approve Bob Mac Capture there; the app cannot grant that approval for itself.

## Updating, Reinstalling, and Rollback

```sh
just bundle "Apple Development: Name (TEAMID)"
just install ~/Applications "Apple Development: Name (TEAMID)"
```

`Scripts/install.sh` fully verifies the newly staged bundle's signature and bundle
identifier *before* touching the installed app, then swaps it into place by renaming the
previous install to a same-directory backup, moving the new bundle in, and only deleting
the backup after the installed copy re-verifies. If the swap or post-install signature
check fails, the script automatically restores the previous app from that backup and
exits non-zero — an interrupted or failed update never leaves `~/Applications` (or
`/Applications`) without a working previous copy. Restart-stage failures are different:
they leave the verified new bundle in place, as described below.

`just install` is the complete update. After the new bundle verifies, it restarts the
selected installed copy if that copy was already running, and only then returns. If that
exact install was stopped, `just install` leaves it stopped. A copy launched from the
other supported install target (`/Applications` versus `~/Applications`) or from
`swift run` / a raw `.build` binary is not touched.

Automatic restart uses the same quit-and-relaunch sequence as
`Bob → Restart Bob Mac Capture`: an unsent draft is discarded, retained canceled drafts
survive, and there is no confirmation dialog. The menu item remains the manual restart
mechanism when you want to relaunch without reinstalling.

When that automatic restart succeeds, the replacement process requests one
`Install complete` notification after `applicationDidFinishLaunching` finishes its normal
setup. Clicking the banner or `Capture` opens the capture panel; dismissing it does
nothing. The banner is best-effort: `just install` never prompts for notification
permission, and missing, denied, or reset authorization is silent and does not change
installer output, restart ordering, or whether the replacement launches. A stopped
install still does not launch or notify. `Bob → Restart Bob Mac Capture` does not show
the install-complete notification.

If the new bundle is installed and verified but the running-process handoff fails,
`just install` exits non-zero without rolling back that verified bundle. The error names
the installed path so you can start that copy, or use `Bob → Restart Bob Mac Capture` if
an old instance is still running.

To roll back deliberately, keep the previous release's commit or tag and rerun
`just bundle`/`just install` from that revision; there is no separate rollback command
because reinstalling the old build is the rollback.

To roll back the Hammerspoon cutover specifically, first turn off **Use production
Control-Shift-Command-I** in Settings so the app returns to Control-Shift-Command-O,
then restore the pre-cutover Hammerspoon files documented in the chezmoi repository.
Do not restore the old binding while the app still owns the production shortcut.

Reinstalling with a **different** signing identity (for example, moving from ad-hoc `-`
to a real Apple Development certificate, or renewing an expired certificate) resets
notification-authorization and launch-at-login trust: macOS ties both to the exact
code-signing identity, not just the bundle identifier. Expect to re-approve notifications
and re-enable launch at login after such a change, and prefer keeping one certificate for
the lifetime of an install rather than alternating between ad-hoc and signed builds.

## Uninstalling

```sh
rm -rf ~/Applications/"Bob Mac Capture.app"   # or /Applications
rm -rf ~/Library/Application\ Support/org.bobs.bob-mac-capture
```

This also removes the launch-at-login registration's target, though macOS may keep a
stale, non-functional Login Items entry until the next login — remove it manually from
System Settings → General → Login Items if it lingers. The app stores only non-sensitive
preferences (bob path, vault path, hotkey choice, and canceled-draft stash capacity) in
`UserDefaults` under the bundle identifier `org.bobs.bob-mac-capture`. Canceled draft
text is stored separately in that Application Support directory (see Privacy).

## Privacy

- Captured text lives only in the panel's in-memory draft and in the arguments passed
  directly to `bob`; it is never logged, written to `UserDefaults`, included in
  notification bodies, or emitted in a signpost or Diagnostics entry.
  `BobClientError.description` explicitly redacts the trailing draft argument from every
  command it echoes.
- Canceled drafts retained with Control-C are stored in
  `~/Library/Application Support/org.bobs.bob-mac-capture/canceled-draft-stash.json`
  (directory mode 0700, file mode 0600). If the stash file is unreadable, it is renamed
  to `canceled-draft-stash.corrupt.json`, which can also hold captured text. They are
  never written to `UserDefaults`, notifications, signposts, logs, or Diagnostics.
  Settings' **Clear Stash...** action and capacity 0 delete both files.
- Diagnostics and Recent Activity in Settings are metadata only — status strings like
  "Ready," "Hotkey conflict," or "Target cache stale," never note content.
- Signposts (see below) carry event names and durations for Instruments, not payloads.
- Wikilink note paths, aliases, heading text, and block previews are read locally by
  `bob` to build completion candidates and are held only in the in-memory completion
  response and the visible row content. They are never logged, written to
  `UserDefaults`, or included in a notification, signpost, or Diagnostics entry — the
  same guarantee the draft itself gets.
- `@route+` task completion metadata, task-section titles, and a user-authored block ID
  are sent only to the local `bob` subprocess. The app never opens or rewrites Markdown
  notes directly; Bob performs the vault write through `capture-task-id`, and the app
  updates the draft only after Bob confirms success.

## Troubleshooting

- **`swift test` fails with `no such module 'XCTest'`**: this is a toolchain selection
  problem, not a missing dependency — XCTest is provided by Apple's matching platform
  tools, not through SwiftPM. Compare `swift --version` against
  `./Scripts/xcode-swift.sh --version`; if they differ or the helper reports a stale
  macOS SDK, update/select Command Line Tools for Xcode 26+ or select a compatible full
  Xcode installation (see Requirements above) and rerun `just test`.
- **"Bob is not resolved"**: Settings shows the resolved path (or "Not resolved") and the
  underlying error. Set an absolute path under "Executable override" or install `bob` at
  one of the default candidate locations, then use "Recheck Bob."
- **A `bob` command times out**: every `bob` invocation is bounded (20s by default); a
  wedged process is terminated automatically rather than leaving the panel stuck, and the
  resulting error names the timed-out command (never the captured text).
- **Pasting feels slow**: with the source content still on the clipboard, run
  `osascript -e 'clipboard info'` and compare the rich flavor sizes with `string`. Then
  run `pbpaste | pbcopy` to rewrite the clipboard as plain text only and paste the same
  characters again. If the plain-text paste is instant, the delay was rich flavor import.
- **Notifications never appear**: confirm Settings → Notifications shows "Authorized," use
  "Send Test Notification," and check Diagnostics → Signing — notification delivery
  requires the installed signed bundle, not `swift run`. If authorization shows "Denied,"
  use "Open System Notification Settings" to re-enable it there.
- **The install-complete banner does not appear after `just install`**: that banner is
  posted only when install restarts an already-running copy, and only if notifications
  are already authorized for the signed bundle. A stopped install, `Bob → Restart Bob
  Mac Capture`, `swift run`, and denied or not-yet-requested authorization are all
  silent by design; installation still succeeds. Check Settings → Notifications and
  Diagnostics → Signing, and look for `install-restart-notification-requested` in
  `log show --signpost --predicate 'subsystem == "org.bobs.bob-mac-capture"'`.
- **Target/route completion is empty or stale**: Diagnostics reports "Target cache stale"
  with the underlying scan error; fix the reported cause (for example, an unreadable
  vault path) and reopen the panel, which retries the refresh.
- **Adding a block ID fails**: duplicate IDs, stale task refs, terminal tasks, and file
  I/O errors are Bob errors. The Add block ID card keeps the selected task and typed ID
  visible so you can edit, retry, or press Escape to return to the refreshed task list.
  The draft is not expanded until Bob confirms the write.
- **Typing does not reach the Add block ID field**: check
  `log show --signpost --predicate 'subsystem == "org.bobs.bob-mac-capture"'` for
  `block-id-focus-claimed` (normal), `block-id-focus-repaired` (the safety net fired),
  or `block-id-focus-claim-failed` (report it).
- **Wikilink completion shows no candidates, or the status bar reports a link
  completion warning**: an empty list with no status change means no note, heading, or
  block matched the query — try a shorter query or check the spelling. A status message
  starting with "Link completion warning:" instead means `bob-cli` skipped one or more
  vault entries (for example, an unreadable note or malformed alias) but still returned
  the candidates it could build; the warning names the specific problem. A `bob` process
  or transport failure surfaces through the normal "Bob is not resolved" / timeout paths
  above rather than as a silent empty list.
- **Capture fails but the draft disappears**: this should never happen — failures always
  preserve the complete draft and destination, and deliberately keep the panel on screen
  to show it. A panel that vanished after Return means the capture landed; the success
  notification names the route it took. Use "Copy Diagnostic" next to the error to
  capture the exact `bob` error for a bug report.
- **Restart reports "Restart failed"**: `Bob → Restart Bob Mac Capture` refuses to quit
  rather than leaving no menu-bar item behind. This fires for two reasons: the process
  is running unbundled (`swift run BobMacCapture` or a raw `.build` binary, which has no
  `.app` to relaunch from) or the installed bundle at the launch-time path is missing.
  Both cases post a "Restart failed" notification and record the reason in Settings →
  Diagnostics; install the app with `just bundle` + `just install` and try again.
- **The `Bob` menu-bar item does not appear** (no crash dialog, hotkey does nothing,
  Settings will not open): the app has no nib, so its entry point
  (`BobMacCaptureMain.swift`) must construct `AppDelegate`, assign it to
  `NSApplication.shared.delegate` itself, and supply its own main menu — nothing in
  `Resources/Info.plist` does this for you. If that wiring regresses, the process
  launches and runs an empty AppKit event loop instead of crashing, so check for a live
  but silent process before assuming the app failed to launch at all:
  - `pgrep -fl BobMacCapture` — confirms whether the process is running at all.
  - `log show --last 5m --predicate 'process == "BobMacCapture"'` — look for the
    `launch-complete` signpost (subsystem `org.bobs.bob-mac-capture`); its absence means
    `applicationDidFinishLaunching` never ran.
  - `~/Library/Logs/DiagnosticReports/` — check for a crash report if the process is not
    running at all.

## Diagnostics and Signposts

The app emits `os_signpost` intervals/events (subsystem `org.bobs.bob-mac-capture`,
category `capture`) around hotkey receipt, panel ordering, editor focus, parse,
completion, preview, submit, block-ID focus claims, plain-text paste
(`paste-plain-text`), notification scheduling, and install-restart notification
requests (`install-restart-notification-requested`), visible in Instruments' Points of
Interest / os_signpost templates. These, and the bounded Recent Activity list in
Settings, are metadata-only by construction — see Privacy above.

## CI

GitHub Actions runs on `macos-26` for pushes to `master` and pull requests. The workflow
checks Swift formatting, `swift build`, `swift test`, bundle assembly, `plutil -lint`,
signature verification, and the bundle identifier. It also launches the bundled app and
requires the `launch-complete` signpost to appear in the unified log before quitting it,
so a broken entry point (no delegate assigned, no menu bar item, no hotkey) fails CI
instead of shipping silently. The installer gate then installs into a temporary `HOME`
while stopped (must not auto-launch), relaunches that exact bundle through a running
reinstall (old PID gone, one new PID, a fresh `launch-complete` and
`install-restart-notification-requested`), and reinstalls once more while stopped
(must stay stopped). An ordinary launch of the installed copy must not emit the
install-restart notification signpost.

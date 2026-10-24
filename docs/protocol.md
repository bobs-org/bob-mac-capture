---
title: "Mac Capture protocol"
description: "Bob Mac Capture subprocess commands, JSON boundaries, capability requirements, and compatibility."
---

Bob Mac Capture owns presentation, process orchestration, and settings. Capture grammar, completion data, previews, and vault mutation belong to `bob` ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)). New capture behavior lands in `bob` and [Capture syntax](https://bobs-org.github.io/reference/capture-syntax/) first; the app then decodes and presents it.

Capabilities are detected per response, never pinned to release numbers: unknown span kinds decode as neutral text, unknown contexts as generic rows, and absent additive fields decode to the behavior in the compatibility table. Upgrade `bob` when a row says so; nothing below invents a minimum release.

## Capability requirements

`bob` must support these contracts before the panel can use them:

- A `bob` build that supports `@@route` / `@@route+block-id` global destination
  declarations anywhere in the draft, `capture-rewrite` (including
  `switch_block_id_separator` and `start_template`), `capture-complete --all-tasks`,
  `capture-task-id`, `capture-pomodoro-name`, the `task_link` completion context for
  `:` picker queries (with `note_kind`, `block_id_suggestions`, `group`, `scheduled`,
  and `pulls_forward` candidate fields), the `task_goto` completion context for a
  whole-draft `/` query (`note_path` and absolute `target` candidate fields), the
  `task_parent` completion context for
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
  create-future-Pomodoro action, `task_toggle` capture JSON, the additive
  `dropped_dependencies` rows and `link_guard` object (`reasons`, `promoted`,
  `detail`, `drop_refused`) on link, toggle, Ensure Next, and link-then-close
  captures, the
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
  `interactive_placeholder` span, `x#name` close near-miss diagnostics, and
  the additive `created_pomodoro` capture summary for new and "again"
  sessions),
  plus Pomodoro close `x` and its additive `pomodoro_close` capture summary,
  plus the project-note `@route^block-id+#pomodoro` marker (the retired
  `@route:block-id+` spelling is a parse diagnostic), the trailing ` :id` /
  ` ^id` project-task tokens (`project_task_block_id` completion context with
  intent `new`, `project_task_link_marker` / `project_task_block_id` parse
  spans, and the additive `project_note.task_links` capture object).
  Bulk templates require Bob's additive `template` / `template_row` parse and capture
  objects, field-indexed `template_placeholder` and `template_field` spans, the
  `template_row` incomplete need, and the `template` route-completion candidate.
  Go To and Control-\ today-Pomodoro landing and Bob Refs Control-Return
  also require bob-plugins **bob-navigation-hotkeys ≥ 2.32.0** (or the
  version that shipped `obsidian://bob-goto-task`). Control-Return landing via
  `obsidian://bob-open-notes` needs **bob-navigation-hotkeys ≥ 2.44.1**,
  deployed to the vault with `bob plugins sync`.
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
  `x`. A close summary whose task, carried, notes, or next fields are absent
  still previews: booleans read as false, arrays as empty, and missing lines as
  zero, and unknown task roles degrade to a neutral row. A close summary whose
  `in_progress`, `park`, `complete`, `drop`, `task_links`, or `index` fields are absent
  still previews as today's unnumbered card: the spec decodes as no selection,
  rows decode as unnumbered, and no hint, summary, or badge renders. Whole-item
  `x` (including the `x*` and `x!` selection forms) reports `pomodoro_close` mode with a `pomodoro_close` span and a
  `{"raw": "x"}` parse spec (`raw` preserves the exact token, `x*` parks
  all numbered links and `x!` completes them); link items keep `pomodoro_link`/`pomodoro_task`
  mode with a `pomodoro_close` span kind over the suffix. A selection-bearing
  close adds `pomodoro_close_in_progress`, `pomodoro_close_park`,
  `pomodoro_close_complete`, and `pomodoro_close_drop` spans, an
  `in_progress`/`park`/`complete`/`drop` parse spec plus additive
  `park_all`/`complete_all` intent flags,
  and `task_links` plus per-row `index` in the capture summary; a dangling
  `,`/`~` reports mode `incomplete` with a `pomodoro_close_task` need and
  an `interactive_placeholder` span instead of an error. A present-but-empty
  `*`/`!` group selects all numbered links left after explicit assignments;
  explicit forms such as `x*1` and `x!1` narrow the action to task 1. Two
  empty wildcard groups compete and need numbers on at least one group. One
  entry may sit on the close line itself (`x wired the lexer` logs to task 1
  for a plain close, or to the first eligible top-level worked link with
  wildcard intent; `x1,3 3 fixed the flake` logs to task 3): an explicit number adds a
  `pomodoro_close_log_index` span in cyan on the close line while the default
  adds none, and a dangling inline number (`x 2`) reports mode `incomplete`
  with a `pomodoro_close_log_text` need and an `interactive_placeholder`
  span over the number. Several entries use ⌃J bullets
  (`x` plus `- 1 wired the lexer`, with `  - …` detail bullets under
  entries), which add a `log` parse spec with the typed entries in order,
  each carrying its `details`. Bullets may omit the number: unnumbered
  bullets log in order to the close's worked tasks (`x3,4` plus `- foo bar`
  plus `- baz bam` writes exactly what `- 3 foo bar` plus `- 4 baz bam`
  writes), and a single worked task takes them all. Bullets are numbered
  all or none, and a leading number is always a task number (to log text
  that starts with a number, number every bullet). Numbered entries add
  `pomodoro_close_log_index` spans in cyan over each entry index while
  positional entries get no index chip; `capture-parse` omits `log[].index`
  for entries `bob capture` resolves against the running session, and the
  app decodes a missing index as nil. Entry and detail text keeps wikilink
  spans but is otherwise neutral prose, and a dangling bullet (`x` plus
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
  task status. `x0*2` reports `Continue none \u00b7 Parked 2`. A dropped (`~<K>`)
  close removes those links from today without carrying or starting them; the
  card strikes and dims dropped rows, summarizes `Dropped 4, 5`, and reads
  "drops from today" for VoiceOver. A dropped row adds a "stays <status>"
  caption naming the lane the task keeps. The `x*`/`x!` all-task selection
  behavior requires the corresponding updated Bob executable. With an
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
  `plan_themes_cap`. `plan_budget` also carries `added_theme_refs`, the hue refs
  for the added names: the `+1 BOB` delta chip wears the first added hue and
  created destination, start, toggle, and project-note rows wear theme pills.
  `pomodoro_name` and `task_toggle_pomodoro_name` spans carry per-component
  `themes` refs, so the editor tints known names behind the unchanged syntax
  color; unknown and exempt names stay neutral. Agenda entries carry `themes`
  refs, so group headers wear pills and the one-row fold wears swatches; home
  dots are untouched. Refs Today rows carry `themes` refs for the same pills.
  The shared catalog, hue, and menu rules are defined in the [Pomodoro themes
  contract](https://bobs-org.github.io/pomodoro-themes/).
  An older Bob that omits `plan_budget`, `role`,
  `plan_themes_after`/`plan_themes_cap`, `added_theme_refs`, span or entry
  `themes`, or `code` still previews and captures;
  the Mac app decodes each as absent and renders the destination row as
  `→ NAME`, omitting only the meter capsules, the cap badge, the strict
  hint, and the theme tints. Agenda and Refs rows from an older Bob render
  the plain name with no pills. A trailing `#now` tag is the ordinary trailing-tag error like any
  other `#tag`, and `#now` typed before the route is plain body text. The `^`
  active-task picker lists In Progress and Next tasks only. An older Bob that
  still sends the `now` flag, the `now_tag` span or completion context, or
  the `now` picker group still previews and captures; the Mac app decodes an
  unknown span as neutral, an unknown context as a generic row, and an
  unknown group as `note`. Saving links to the reading queue needs a Bob that
  emits the `ref` capture kind with the additive `ref` object, `ref` parse
  mode, and the `ref_url` span. An older Bob keeps capturing a bare link as an
  ordinary inbox task; the Mac app decodes the missing `ref` object as no
  reference preview and keeps the standard card, so upgrade Bob before
  queueing links. Filing a link needs a Bob that resolves the canonical
  parent: the additive `ref.parent` object (`route`, `label`, `kind`,
  `source`, `alias`) on capture results, `ref_parent` (`token`, `source`)
  on `capture-parse` `ref` items, and `project_name_aliases` on
  `capture-targets` entries. A bare URL that will queue under the default
  parent opens the route list on its own with the header **File under**:
  cached inbox, area, and project targets with the last-used parent first,
  then `mac_inbox`; typing filters with aliases included
  (`bob · aka bob-cli`). Accepting inserts ` @<route>` at the end of the
  draft; Esc keeps the default (`→ mac_inbox · file it later`) and the list
  does not reopen until the URL changes. Library hits (`in_library`,
  `in_intake`, `clipping`, `duplicate`) never open it. The queued preview
  reads `📖 Queue · example.com/essay → sase` (plus the parent's kind for an
  explicit `@route`), and the confirmation and notification read
  `Queued for reading → sase`. The last-used parent is remembered after a
  successful submit. Route completion everywhere ranks alias matches after
  prefix route matches. An older Bob that omits `ref.parent`,
  `ref_parent`, or `project_name_aliases` still previews and captures; the
  Mac app decodes each as absent, keeps today's wording, never auto-opens
  File under, and matches routes without aliases, so upgrade Bob before
  filing links. Inbox routing needs a Bob that reports the additive
  `inbox_route` object (`supported`, candidates, and destinations) on every
  capture JSON and accepts repeated `--inbox-route KEY=<relative_path>` (or
  `KEY=` to keep) answers plus the hidden `--require-inbox-route-choice`
  guard; without it the app captures without asking.

The app never invokes a login shell to find `bob`. A Settings override must be an
absolute executable path.

The executable search paths and the Settings override live in [Install](install.md#requirements).

## Timeouts and guards

Every `bob` invocation is bounded by a 20-second timeout (`BobProcessClient.defaultTimeout`)
  that terminates and reaps a wedged process instead of leaving the panel waiting
  indefinitely; a fired timeout surfaces as an actionable `BobClientError.timedOut`. Quit
  cancels every outstanding invocation via `cancelActiveProcess()`.

If Bob rejects the exact `--refuse-override` flag as an
unexpected argument (exit 2), the app retries without that guard and remembers the
answer for that executable. `--require-pull-in-choice` is never retried: it goes out
only after a preview from the same executable advertised `pull_in.supported`, so an
older Bob never sees it; it also shows a note that this Bob lacks successor-choice
checks. `--require-inbox-route-choice` goes out under the same positive gate (a
preview, or any decoded capture JSON, that carried `inbox_route.supported == true`,
remembered per executable identity), and an older Bob that still receives it retries
without the flag the same way. Other failures and explicit stale-key refusals are never
retried. The app only sends explicit offer keys from a matching preview or write-free
refusal back to `bob capture`. An older bob never overrides on `=`, so retrying without
`--refuse-override` is safe.

If Bob rejects `-a` / `--attended` on `ref scan` as an unexpected argument (exit 2),
the app retries without that flag and remembers the answer for that executable, the
same way it remembers the capture guard flags.

Template saves send `--template-origin` only after a successful template-list request from that same executable; see [Saved templates](saved-templates.md).

## Required commands

These must exist; without them the feature they serve stays hidden or refuses with `bob`'s own error:

- `capture-parse --format json` (spans, needs, replacements, ranges, `cursor_after`)
- `capture-complete --all-tasks --cursor BYTE --format json` (candidates, replacements)
- `capture-rewrite --cursor BYTE --format json` (marker absorption, separator toggles, relation-label attachment, template start)
- `capture --dry-run --no-clip --format json` (live preview) and `capture --format json` (submit)
- `capture-pomodoros --format json --tasks` (agenda, counts, landing); plain `capture-pomodoros` only feeds the close-comma count on older builds
- `capture-task-id` / `capture-pomodoro-name` (Add block ID / Name Pomodoro prompts)
- `capture-targets` (route list), `capture-templates list` / `save` (template shelf)
- `ref list -R all -A -f json` (Refs snapshot, schema 1; add `-g` while any row still lacks an `added` date or git instant)
- `plan -f json` (Refs Today join, schema 2)
- `ref scan -a -w -f json` (Refs scan report, schema 1; `-a` is omitted after an older bob rejects it)
- `ref show <note-path> -f json` (inspector hydration)
- `ref rename` (Rename card)
- `vault-sync -q` (Refs pull on panel show and before ⌘R)

Bob Refs ⌘S and the enabled Highlights-save trigger use this scan command.

Every writing `bob ref scan` that acquired the scan writer lock writes that JSON
envelope to `<state>/bob-cli/ref/last-scan.json` (`XDG_STATE_HOME`, else
`~/.local/state`) and, on macOS, posts the Darwin notification
`org.bobs.bob.ref.scan-finished`. Bob Refs observes that name with
`notify_register_dispatch`, reads the receipt off the main thread (bounded at 4 MB),
and ignores a duplicate content hash. Launch never reads a receipt.

## Optional commands

These features stay hidden when the installed `bob` does not provide the command:

- `capture-related --format json -- DRAFT` (settled similar-task matches and draft anchors, schema 1)

## Optional fields

Absent fields decode tolerantly and only hide their own row, badge, or offer:

- `creates_pomodoro`, `pomodoro_start`, `pomodoro_adjust`, `pomodoro_shift`, `pomodoro_close` (plus `log`, `details`, `typed_work_log`, `typed_work_log_details`)
- `pomodoro_start.override`, `toggle_behavior`, `toggle_direction` with `status_changed`
- `plan_budget`, destination `role`, `plan_themes_after`, `plan_themes_cap`, `code`, `added_theme_refs`
- span `themes` (`pomodoro_name`, `task_toggle_pomodoro_name`), agenda entry `themes`, Refs Today row `themes`
- `ref` with `ref.parent`, `ref_parent`, `project_name_aliases`
- Refs list fields `blocked`, `task`, `added_at`; snapshot cache key `git_added_at`; copy-card `marker_id`
- Scan report fields `generated_at`, `summary.held`, `held[]`, `notes[].marker_write` (`mode`, `editor_saved_first`, `status.from`/`to`)
- `block_id` object, `picker` descriptor, `parent_replacement`, `pomodoro_start_name` context
- `open_notes`, `homes`, `task_links`, successor-offer payloads
- `inbox_route` (candidates, destinations, `repaired_files`, `renamed_block_ids`, `needs_reconcile`) and `refused` detail on `inbox_route_refused`
- `relation_grammar`, relation-label `relation` token metadata and `owner`, `relation_updates`, `linked_from_line_updates`, `minted_relation_block_ids`, `mirror_skipped`, relation-label `count` / `typed`
- relation vocabulary: label `key` / `inverse` / `hide_replacement` / `existing` / `hidden`, `hidden_count`, `one_off`, `bob relations list` / `hide` / `unhide`, `relation_label_hides[]`, structured capture warnings, `bob relations rename` preview/write with counts, `label_range` / `hidden` on `relations[]`
- Retired inputs (`now` flag, `now_tag` span, `now` picker group) decode as neutral: unknown spans as neutral text, unknown contexts as generic rows, unknown groups as `note`

## Compatibility

| Feature or field | Expectation | When absent | Reader action |
| --- | --- | --- | --- |
| `@@route` / `@@route+block-id` declarations | Unmarked items route to the declaration | Ordinary draft capture; bare markers report the local `bob` error or an empty list | Upgrade `bob` for declarations |
| `capture-rewrite`, `switch_block_id_separator`, `attach_relation_label`, `start_template` | `@@` absorbs markers; `^` / `:` toggle the separator; `|` attaches to an eligible relation token; `@@@` starts a template | With an older bob, the third `@` types literally; a space before `|` stays literal and only `~note:id|` opens the relation card; other rewrites follow that bob's behavior | Upgrade `bob` for relation-label attachment and template start |
| `capture-complete --all-tasks` | Full candidate lists | Empty list or local `bob` error | Upgrade `bob` |
| `task_link` / `task_goto` / `task_parent` / `task_block_id` contexts | Picker rows with replacements and intents | No rows; calm browse hint instead of a dry-run error | Upgrade `bob` |
| `picker` descriptor, `parent_replacement` | Vault-wide `+` picks, ID-less splice | Inline list only; prompt asks to update `bob` | Upgrade `bob` |
| `pomodoro_name`, `task_section` completion | `#` completion after resolved markers | No rows until `bob` is upgraded | Upgrade `bob` |
| `creates_pomodoro` | Explicit Create row | Captures without the explicit row (decoded false) | Upgrade `bob` to see it |
| `pomodoro_start` / `pomodoro_adjust` / `pomodoro_shift` | Session, adjust, and shift rows | Omitted rows; malformed suffixes surface `bob`'s diagnostic | Upgrade `bob` for `=` / `+N` / `++N` |
| `pomodoro_close` with `log` entries | Close card with typed Work Log | Standard card; no close preview | Upgrade `bob` before `x` |
| `toggle_behavior` | Ensure Next vs Set Next / Open labels | Two-way labels; status and relocation still exact | Upgrade `bob` for exact labels |
| `plan_budget`, `role`, theme caps | Meter capsules, badges, strict hint | Destination row only (`-> NAME`) | Upgrade `bob` for meters |
| `added_theme_refs`, span/entry/row `themes` | Pill and swatch tints in the editor, agenda, previews, and Refs Today | Plain names; neutral pills only where a budget exists | Upgrade `bob` for theme tints |
| `ref` object | Queue preview card, footer action | Ordinary inbox task | Upgrade `bob`; `-R` disables queueing |
| `ref.parent`, aliases | File-under prompt, alias-ranked routes | No auto-open; prefix matching only | Upgrade `bob` for filing |
| `ref list` schema 1, optional `-g` | Refs snapshot with git instants | Refresh fails on any other schema; `-g` omitted until a row still lacks `added`/`added_at` | Upgrade `bob` for Refs |
| `blocked` on a Refs row | Blocked rows sort last in Next/Ready | Decoded as not blocked | Upgrade `bob` for blocked ranking |
| `task` on a Refs row | Today joins on `(path, block_id)`; ⌃↵ opens the reading task | Note-path join; two tasks on one parent can both light up; ⌃↵ beeps | Upgrade `bob` for task join |
| `added_at` | Timed Newest groups and captions | Nil; day-only or undated ranking | Upgrade `bob` for instants |
| `plan -f json` schema 2 | Today pills from the ledger | Last good Today; footer can say Update failed | Upgrade `bob` for Today |
| `ref scan -w -f json` schema 1 | Scan report, Just scanned, notifications | Banner or "This bob can't report scans yet" | Upgrade `bob`; retry ⌘S |
| `ref scan -a` / `--attended` | Attended scan: never hold marker writes because Highlights is in use | Retry without `-a` and remember for that executable | Upgrade `bob` for attended scans |
| Scan `generated_at`, `summary.held`, `held[]`, `notes[].marker_write` | Open-PDF footer clauses, busy banner, grouped notifications | Decoded empty; scan still lists created notes | Upgrade `bob` for coordinated PDF writes |
| `ref show` | Hydrated inspector notes, tasks, outline | Basic inspector plus dim "Notes unavailable" | Upgrade `bob` for notes |
| `ref rename` | Rename card writes through `bob` | Card stays open with `bob`'s refusal | Upgrade `bob` for rename |
| `vault-sync -q` | Background Refs pull | Pull failure is logged only; list stays | Upgrade `bob` for pull |
| `marker_id` | Copy-card `I` row | `I` asks for a newer `bob`; other copy rows still work | Upgrade `bob` for marker IDs |
| `open_notes` | Control-Return lands on captured lines | Tabs open without landing | Upgrade `bob`; needs plugin 2.44.1+ |
| `--tasks` on `capture-pomodoros` | Agenda, counts, `=#name` names | Agenda hidden; counts from plain output | Upgrade `bob`, then Recheck |
| `pomodoro_start_name` | Start list for `=#name` | No rows | Upgrade `bob` |
| Template spans, `@@template:` | Template rows, shelf, preview capsule | Ordinary drafts keep working; refuse before writing | Upgrade `bob` for templates |
| `override`, guard flags | Orange banner; guarded commit; choice card | Plain start; retry without the flag is remembered | Upgrade `bob` for overrides |
| `pomodoro_blocks`, `task_blocks` | Full block views below the stack | Standard item stack | Upgrade `bob` for blocks |
| Successor offers | Grouped Pull-In choice card | Single legacy wording | Upgrade `bob` for offers |
| Inbox routing | Route card before submit | Captures without asking | Upgrade `bob` |
| `sub_bullet_depths`, `global_destination`, `items` | Exact children; one shared-scope line | Depth 1; per-item targets | Upgrade `bob` for shared scope |
| `homes` | Derived names and home chips | Previous naming | Upgrade `bob` for names |
| Close-comma assist field | Auto-inserted `,` | Assist off; digits type normally | Upgrade `bob` for assists |
| `relation_to` / `relation_from` completion | `~` / `~~` picker rows with replacements and intents | No rows; calm browse hint instead of a dry-run error | Upgrade `bob` for relations |
| `relation_label` completion and `relation` metadata | Relation card suggestions with counts, typed row, token range, direction, and owner | Without the metadata, the app uses its legacy token scan; without the completion context, no card opens | Upgrade `bob` for relation labels and exact token ranges |
| `relation_label` `key` / `inverse` / `hide_replacement` / `existing` / `hidden`, `hidden_count`, `one_off` | Canonical keys, inverse phrases, `||` insertions, typed validation flags, Hidden pill, one-off mode | Local label folding, no inverses, `|` insertions only, no Hidden section or pill, no one-off mode | Upgrade `bob` for the relation vocabulary |
| `bob relations list -f json`, `hide`, `unhide` on the `relation-label-pref` lane | Hidden section, ghost hide/unhide rows with ⌃D undo | No Hidden pill; Ctrl-D and Ctrl-H give the update hint | Upgrade `bob` to hide relation labels |
| `bob relations rename -f json` dry run on the `relation-rename-preview` lane, apply on `relation-label-pref` | Rename mode with live preview, merge confirm, draft fix-up from `label_range`s | Ctrl-R gives the update hint | Upgrade `bob` to rename relation labels |
| `relation_label_hides[]`, structured `hides_existing_relation_label` warning | Amber preview row, card warning, `· hid` notification suffix | No hide rows; structured warnings decode as text | Upgrade `bob` for one-off hides |
| `relation_grammar` | `~` parses with relation spans; capability warning stays hidden | Calm `predates ~ links` warning; first ⌘↩ only shows it | Upgrade `bob` for `~` |
| `relation_updates[]`, `linked_from_line_updates[]`, `minted_relation_block_ids[]`, `mirror_skipped[]` | 🪢 preview rows, managed-line suppression, separate notification counts | Legacy preview without relation rows; notifications omit relations | Upgrade `bob` for relation previews |
| `capture-related` | A settled Similar tasks band beneath matching task cards | Band stays hidden; ordinary preview and capture continue | Upgrade `bob` to show similar tasks |

The app waits 350 ms after an edit before requesting `capture-related`. An older `bob`
that rejects the command is remembered for that executable identity, so the app keeps
the band hidden without retrying on later drafts. Changing the executable identity
rechecks support.

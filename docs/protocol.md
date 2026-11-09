---
title: "Mac Capture protocol"
description: "Bob Mac Capture subprocess commands, JSON boundaries, capability requirements, and compatibility."
---

Bob Mac Capture owns presentation and process orchestration. Bob owns capture grammar, completion, previews, and vault mutation ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)). New capture contracts land in `bob` first; the app decodes and presents them.

Capabilities are response-driven: unknown spans render neutral, unknown contexts generic, and missing fields follow the compatibility table. Upgrade `bob` where noted.

## Capability requirements

`bob` must support these contracts before the panel can use them:

- A `bob` build that supports route-only `@@route` global destination declarations
  anywhere in the draft, `capture-rewrite` (including
  `switch_block_id_separator` for `^`, `:`, and `+`),
  `capture-complete --all-tasks`,
  `capture-task-id`, `capture-pomodoro-name`, the `task_link` completion context for
  `:` picker queries (with `note_kind`, `block_id_suggestions`, `group`, `scheduled`,
  and `pulls_forward` candidate fields), the `task_goto` completion context for a
  whole-draft `/` query (`note_path` and absolute `target` candidate fields), the
  `task_parent` completion context for leading and prose-terminal `+` (with the
  additive `picker` descriptor, including `action_continuation_aliases`), the same descriptor on scoped `@route+` `task` responses,
  `parent_replacement` on `capture-task-id` for vault-wide ID-less picks,
  `drawer` completion for `@route+block-id#`, `pomodoro_name` completion, the
  `task_block_id` completion context, the additive `block_id` object, the
  additive `creates_pomodoro` action, `task_toggle` capture JSON, the additive
  `dropped_dependencies` rows and `link_guard` object on link captures, the
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
  plus project-note `@route^block-id@#pomodoro` (create) and
  `@route:block-id@#pomodoro` (offer). Retired `@route^block-id+` and
  `@route:block-id+` forms produce diagnostics. The seal span is
  `project_note_marker` or `project_note_offer_marker`; the separator is
  `project_note_separator`. Each marker span carries the `project_note`
  modifier (`create`/`offer`) for its manila chip: absent modifiers paint
  brown without wash; unknown modifiers wash without recoloring.
  Trailing ` :id`/` ^id` tokens use `project_task_block_id` completion intent
  `new`, `project_task_link_marker`/`project_task_block_id` spans, and
  `project_note.task_links`. Offer JSON adds `project_note.form: "offer"` and
  `project_note.successors` with Pull-In keys. Picked rows also enter
  `task_links`; count them once as Linked, never again as pulled-in successors.
  Either separator plus seal uses existing `project_note` completion intent;
  new intents would be misread as `link` by older Macs.
  Lists under a lone `@file` or `@file#section` header (grammar 6; the gate requires
  grammar 5) add the `list` object on `capture` results and `capture-parse` items,
  the `list_item` need, and `block_id.owner_line` / `block_id.splice` on
  `project_task_block_id` completions. The app applies the splice and groups results
  by `list` ([Capture lists](capture-lists.md)); it never splits a draft or places an ID itself.
  Bulk templates require Bob's additive `template` / `template_row` parse and capture
  objects, field-indexed `template_placeholder` and `template_field` spans, the
  `template_row` incomplete need, and the `template` route-completion candidate.
  Task Wikilink picks require `capture-parse` spans
  `wikilink_task_delimiter` / `wikilink_task_query` to request the `wikilink_task`
  completion context (with the additive `link_target` candidate field, Bob-order
  groups, and picker descriptor) and `wikilink_replacement` on `capture-task-id`
  results. An older Bob sends no task-wikilink spans, so the app requests no
  completion and `((` stays plain text; upgrade `bob`.
  Go To and Command-\ today-Pomodoro landing and Bob Refs Control-Return
  also require bob-plugins **bob-navigation-hotkeys ≥ 2.32.0** (or the
  version that shipped `obsidian://bob-goto-task`). Control-Return landing via
  `obsidian://bob-open-notes` needs **bob-navigation-hotkeys ≥ 2.44.1**,
  deployed to the vault with `bob plugins sync`.
  Missing `pomodoro_start`/`pomodoro_close` omits its card; missing summary arrays
  decode empty, booleans false, and unknown close roles neutral. A close without
  selectors stays unnumbered. Whole-item
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
  report a top-level `plan_budget` object with a before/after link meter and
  link-cap warnings that fire only while the batch grows the meter past its cap;
  the same destination carries a `role` of `current`, `next_up`, `named`, or
  `created`. The daily plan caps Task Links only, so the app shows no type
  meter, type delta, or type-cap badge or hint; an older Bob's `themes` meter,
  `added_themes`, `plan_themes_after`/`plan_themes_cap`, `plan_theme_cap_exceeded`
  warnings, and refusals are decoded as absent or ignored. `plan_budget` also
  carries `added_theme_refs`, the hue refs for the added names: created
  destination, start, toggle, and project-note rows wear theme pills.
  `pomodoro_name` and `task_toggle_pomodoro_name` spans carry per-component
  `themes` refs, so the editor tints known names behind the unchanged syntax
  color; unknown and exempt names stay neutral. Agenda entries carry `themes`
  refs, so group headers wear pills and the one-row fold wears swatches; home
  dots are untouched. Refs Today rows carry `themes` refs for the same pills.
  The shared catalog, hue, and menu rules are defined in the [Pomodoro themes
  contract](https://bobs-org.github.io/pomodoro-themes/).
  An older Bob that omits `plan_budget`, `role`,
  `added_theme_refs`, span or entry `themes`, or `code` still previews and
  captures; the Mac app decodes each as absent and renders the destination row as
  `→ NAME`, omitting only the TODAY badge and the theme tints. Agenda and Refs rows from an older Bob render
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

Grammar 12 adds past-work `x=` recording: `pomodoro_past` mode, spans, and
  summaries with windows, trims, and `pomodoro_past_trim` warnings, decoded
  tolerantly with no synthesized top-level close and an unchanged gate.

Grammar 14 segment suffixes precede `!` / `=`: `~` tail, `~N` / `~N+`
segment start/end, `~~` head. Bob returns spans, candidates, resolved segment/pin,
and cuts. Segment-ending `-` rewrites to `~`; stale-window guards refresh previews.

The app never invokes a login shell to find `bob`. A Settings override must be an
absolute executable path.

The executable search paths and the Settings override live in [Install](install.md#requirements).

## Move-choice submission

`move_choice.supported` gates `--move-in KEY,:KEY|none`, sent before `--pull-in`.
[Move-card protocol](task-pickers.md#move-card-protocol) documents slots, refusals,
answer chaining, and optional decoding.

## Successor verdict submission

`pull_in.close.supported` gates `--complete-offer` and `--cancel-offer`.
Refusals reopen intact; stale picks refresh once and never retry writes.

| App × Bob | Behavior |
| --- | --- |
| New × new | Move → Pull-In → inbox → capture |
| Old × new | Unanswered `^^` refuses before writing |
| New × old | Warn once; second submit captures literally without `--move-in` |
| Old × old | Literal task |

## Timeouts and guards

Every `bob` call has a 20-second timeout; quit cancels outstanding calls.

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

- `capture-parse --format json` (spans, needs, replacements, ranges, `cursor_after`; records add `record`)
- `capture-complete --all-tasks [--closed-tasks] [--next-missing-field] [--record-field KEY] --cursor BYTE --format json` (candidates; records add `record` and `continuation`)
- `capture-rewrite --cursor BYTE --format json` (marker and separator rewrites, relation-label attachment, sigil aliases including spaced `.` → `@`/`&` and `;` → `:`/`*`, template start)
- `capture --dry-run [--no-clip] --format json` (live preview; `--no-clip` omitted unless the accepted parse has a `%c` span) and `capture --format json` (submit)
- `capture-pomodoros --format json --tasks` (agenda, counts, landing, `max_task_link_count`); plain `capture-pomodoros` also reports the bound on new builds and supplies the running count for older-bob fallback
- `capture-task-id` / `capture-pomodoro-name` (Add block ID / Name Pomodoro prompts)
- `capture-targets` (route list), `capture-templates list` / `save` (template shelf)
- `ref list -R all -A -f json` (Refs snapshot, schema 1; add `-g` while any row lacks an `added` date or git instant)
- `plan -f json` (Refs Today join, schema 2)
- `ref scan -a -w -f json` (Refs scan report, schema 1; `-a` omitted after older bob rejects it)
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
- `plan_budget`, destination `role`, `code`, `added_theme_refs`
- span `themes` (`pomodoro_name`, `task_toggle_pomodoro_name`, `task_type`), agenda entry `themes`, Refs Today row `themes`
- `task_type` completion context, top-level `subject` (`new`/`existing`), candidate `current` / `inherited` / `effect` / `refused`
- `task_theme.action` `kept`, `type_relocation` (`outcome`, `from`, `to`)
- `configured` on theme refs and `themes list` rows; `configured_themes` on `themes list`; `hue_source` `config` / `unconfigured`; structured `theme_not_configured` warnings on capture and `capture-pomodoro-name`
- `ref` with `ref.parent`, `ref_parent`, `project_name_aliases`
- Refs list fields `blocked`, `task`, `added_at`; snapshot cache key `git_added_at`; copy-card `marker_id`
- Scan report fields `generated_at`, `summary.held`, `held[]`, `notes[].marker_write` (`mode`, `editor_saved_first`, `status.from`/`to`)
- `block_id` object, `picker` descriptor, `parent_replacement`, Parent Task continuation metadata, `pomodoro_start_name` context
- `wikilink_task` `link_target`, `wikilink_replacement`
- `open_notes`, `homes`, `task_links`, successor-offer payloads
- `inbox_route` (candidates, destinations, `repaired_files`, `renamed_block_ids`, `needs_reconcile`) and `refused` detail on `inbox_route_refused`
- `relation_grammar`, relation-label `relation` token metadata and `owner`, `relation_updates`, `linked_from_line_updates`, `minted_relation_block_ids`, `mirror_skipped`, relation-label `count` / `typed`
- relation vocabulary: label `key` / `inverse` / `hide_replacement` / `existing` / `hidden`, `hidden_count`, `one_off`, `bob relations list` / `hide` / `unhide`, `relation_label_hides[]`, structured capture warnings, `bob relations rename` preview/write with counts, `label_range` / `hidden` on `relations[]`
- Past fields: segment/pin, windows/cut, candidate bounds/repair, stale refusal
- Record: `record`, `continuation`, `type`/`emoji`/`count`
- Retired inputs (`now` flag, `now_tag` span, `now` picker group) decode as neutral: unknown spans as neutral text, unknown contexts as generic rows, unknown groups as `note`

## Compatibility

| Feature or field | Expectation | When absent | Reader action |
| --- | --- | --- | --- |
| `@@route` declaration | Unmarked items route to the declaration; items retain their own route overrides | Ordinary draft capture; bare markers report Bob's local error or an empty list | Upgrade `bob` for declarations |
| `capture-rewrite`, `switch_block_id_separator`, `attach_relation_label`, `expand_sigil_alias`, `toggle_relation_direction` | Rewrites markers, relations, `.` → `@`/`&`, `;` → `:`/`*`, Parent Task commas, and `x`/`s` outcomes | Older Bob leaves aliases literal; older apps lack fast modifier escapes and restores | Upgrade `bob` |
| `project_note` span modifier, `project_note_separator` and `project_note_offer_marker` spans, the `@` seal | Chip behind the sealed marker (brown name/seal; green `:`/`@` on offers) | Older Bob omits the modifier; an older app shows a yellow seal and neutral separator, without wash | Upgrade `bob` for the chip; upgrade the app to paint it |
| `capture-complete --all-tasks` | Full candidate lists | Empty list or local error | Upgrade `bob` |
| `--closed-tasks` in Go To | Command-X switches to closed rows | Older Bob keeps open rows and shows the update hint | Upgrade `bob` |
| `task_link` / `task_goto` / `task_parent` / `task_block_id` contexts | Picker rows with replacements and intents | No rows; calm browse hint instead of a dry-run error | Upgrade `bob` |
| `picker` descriptor, `parent_replacement`, Parent Task continuation metadata | Vault-wide `+` picks, ID-less splice, comma alias, and accept-and-continue | Inline list only; comma filters and Shift-Return stays consumed | Upgrade `bob` |
| `pomodoro_name` completion | `#` completion after resolved markers | No rows until `bob` is upgraded | Upgrade `bob` |
| `creates_pomodoro` | Explicit Create row | Captures without the explicit row (decoded false) | Upgrade `bob` to see it |
| `pomodoro_start` / `pomodoro_adjust` / `pomodoro_shift` | Session, adjust, and shift rows | Omitted rows; malformed suffixes surface `bob`'s diagnostic | Upgrade `bob` for `=` / `+N` / `++N` |
| `pomodoro_close` with `log` entries | Close card with typed Work Log | Standard card; no close preview | Upgrade `bob` before `x` |
| `pomodoro_close.closed_name`, `next_pomodoro.shed` | Close card names the narrowed closed session and the types shed from its continuation | Older Bob omits these details | Upgrade `bob` for merged-session close names |
| `toggle_behavior` | Ensure Next vs Set Next / Open labels | Two-way labels; status and relocation still exact | Upgrade `bob` for exact labels |
| `plan_budget`, `role` | TODAY badge and link-cap warnings | Destination row only (`-> NAME`) | Upgrade `bob` for the TODAY badge |
| `added_theme_refs`, span/entry/row `themes` | Pill and swatch tints in the editor, agenda, previews, and Refs Today | Plain names; neutral pills only where a budget exists | Upgrade `bob` for theme tints |
| `configured`, `configured_themes`, `hue_source` `config`/`unconfigured` | Dashed unconfigured pills, Name-it chips from the vocabulary, `theme_not_configured` captions | Today's pills; Name-it shows Recent as before; no unconfigured warning | Upgrade `bob` for configured themes |
| structured `theme_not_configured` warning | Orange caption with the unconfigured pill in every settled preview and in Name-it | Absent; start/close cards still show other warning strings | Upgrade `bob` for the warning |
| `theme_suggestion` on `capture-complete` (`pomodoro_name`), `suggested` + `suggestion_label` on candidates | Suggested row preselected with `Suggested · <reason>` secondary, `Suggested` header on a suggested create row, reason in accessibility label | First row selected; no reason shown | Upgrade `bob` for suggestions |
| `task_theme` on `capture --format json` items | `type → X · <inherited>` / `type cleared · <inherited>` / `type X · <source>` (`kept`) line in new-task, link, toggle, and relationship previews, VoiceOver summaries, and notifications (`type FIX` on set/kept) | No type line | Upgrade `bob` for type writes |
| `type_relocation` on `capture --format json` items | Ledger line (`BUILD → FIX · running entry renamed`, `moved under FIX`, …) beside the type row | No ledger line | Upgrade `bob` for typed relocation |
| `task_type` completion context, `subject`, candidate `current` / `inherited` / `effect` / `refused` | Compact type menu with header, consequence footer, Ctrl+D hide/show, refused typed rows as no-ops | No task-type menu or refusal details | Upgrade `bob` for `#` completion |
| `grammar` ≥ 5 on `capture-parse` | Capture with whole-item `=/` split and `=*` merge syntax, along with earlier capture grammar | Capture disabled; "Update bob to use Pomodoro split and merge syntax"; the draft stays | Upgrade `bob` for split and merge |
| `grammar` 12 / 14, `pomodoro_past` / `pomodoro_past_segment`, `--expect-past-windows` / `pomodoro_past_windows_changed` | Past stacks/windows/trims; segment picker/card; stale preview refresh | Older Bob omits past cards and the stale guard | Upgrade `bob` for past segments |
| `pomodoro_split` / `pomodoro_merge` spans, modes, and summaries | Split/merge previews show before/after names, created/absorbed entries, and destination | Older Bob omits previews; these tokens do not parse | Upgrade `bob` for split and merge |
| `source_role`, `absorbed[].role`, and `explicit` on `pomodoro_merge` | Implied-pick **Current** / **Next** capsules and the `Same as` caption | Older bob omits them and the card renders as before | Upgrade `bob` for implied-merge captions |
| `pomodoro_split_type` / `pomodoro_merge_dest` needs and completion contexts | Bob's candidates drive the type and destination pickers | No picker rows; the incomplete draft stays visible | Upgrade `bob` for split and merge pickers |
| `drawer` completion context, `target`, candidate `group` / `detail` / `entry_count` / `note_count` / `last_seen` / `creates` / `refused` / `consequence` | New drawer in This task/Recent groups; Bob's counts; refused rows dim and no-op on Return; selected-row consequence footer | Older Bob lacks the context (requires grammar 5); without `detail`, hide counts; without `consequence`, keep the key hint | Upgrade `bob` for the full menu |
| `drawer` object on a sub-bullet capture item (`title`, `key`, `created`) | `new drawer` capsule beside the item header and the drawer title in summaries | Older Bob responses omit drawer-specific header details and the capsule | Upgrade `bob` for the capsule |
| `directive` completion context, `initial_selection: none` | `%` menu with Bob's token, name, summary, and detail; Return captures as typed; Tab takes the first row | Older bob omits the context, so `%` stays ordinary text; omitted `initial_selection` keeps first-row selection | Upgrade `bob` for `%` menus |
| `block_id.owner_line`, `block_id.splice` on `project_task_block_id` | Accepted nested-line IDs land on the owning task line; caret returns to the typing point; card names the owner | Uses the typing-line `replacement` range, as before | Upgrade `bob` for nested-line prompts |
| `list` object on `capture` results and `capture-parse` items | One capsule per list (`3 tasks → dev.md`) with the list's results stacked beneath it | Results stack with dividers and no capsule | Upgrade `bob` for list capsules |
| `list_item` need | A lone header over no bullets shows a calm hint, and the newline key starts the first bullet | An older bob never reports it (a lone header is a literal inbox task there), so the newline key inserts a bare newline | Upgrade `bob` for lists |
| `type` on `pomodoro_link_destination` | ` · <label>` suffix on the ledger and day-file destination rows (`Linked under CHORE · default type`) | Destination rows without the label | Upgrade `bob` for typed placement |
| `merged` on `pomodoro_link_destination` | Link preview reports the added type and merged destination (`merged FIX into BUGS + FIX`) | No merge row | Upgrade `bob` for merged landing details |
| `theme_suggestion` on `ref today`, `suggested` + `suggestion_label` on rows | Suggested row preselected with reason in `rowMeta`; synthetic `New X Pomodoro` row first when `create`; Return on a suggested non-default row sends its entry | Default row selected; Return sends `.automatic`; no synthetic row | Upgrade `bob` for suggestions |
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
| `--tasks` on `capture-pomodoros` | Agenda, counts, `=name` names | Agenda hidden; counts from plain output | Upgrade `bob`, then Recheck |
| `pomodoro_start_name` | Start list for `=name` | No rows | Upgrade `bob` |
| Template spans, `%t` | Template rows, shelf, preview capsule | Ordinary drafts keep working; `%t` may be refused before writing | Upgrade `bob` for templates |
| `override`, guard flags | Orange banner; guarded commit; choice card | Plain start; retry without the flag is remembered | Upgrade `bob` for overrides |
| `pomodoro_blocks`, `task_blocks` | Full block views below the stack | Standard item stack | Upgrade `bob` for blocks |
| `task_complete.unblocked`, `pomodoro_close.unblocked`, `project_note.successors` | Grouped Pull-In choice card; project offers show a New project context and task preview rows | Single legacy wording | Upgrade `bob` for offers |
| `task_complete.keep_moving`, `pomodoro_close.keep_moving` | ⏭ Keep-moving section with the last-planned caption, ready-task lanes, folded reasons, choice keys, and `forward.end.fill` block-diff badge; notifications name the project | Missing arrays decode empty; existing successor offers keep working | Upgrade `bob` for keep-moving offers |
| `relation_successors`, `relation_held`, `relation_check` on capture items, task completion, Pomodoro close, and nested relation completions; row `relation` `{label,key,event,after}` and `offer.after` | Relation rows join ordered Pull-In groups; held/check notices are passive; selected-offer counts and notifications reflect relations. Held reasons: `waits_on`, `waits_for`, `scheduled`, `project`; checks: `checked` or `unavailable` | Missing arrays decode empty; absent check state is silent; malformed optional metadata drops while the offer row remains | Upgrade `bob` for relation successors |
| `pull_in.copy` `{title,capsule,glyph}`, group `copy` `{title,why,tag,fold,glyph}`, `after`, `label`, `event`, and `folded.already_started` / `waits_for` | Bob supplies chooser title, capsule, reason, tag, fold, glyph, relation target identity, and folded-reason line | Missing copy uses legacy per-group Swift wording/order; missing group metadata or fold counts adds no copy | Upgrade `bob` for Bob-authored Pull-In copy |
| Block-diff `reason: relation`, task-block role `relation_successor` | A `link` badge with “Offered by your relation link” help, and relation-successor task styling | Unknown reasons and roles keep their existing neutral fallback | Upgrade `bob` for relation block cues |
| Inbox routing | Route card before submit | Captures without asking | Upgrade `bob` |
| `sub_bullet_depths`, route-only `global_destination`, `items` | Exact children; batch route declaration and per-item route overrides | Depth 1; per-item targets | Upgrade `bob` for global declarations |
| `homes` | Derived names and home chips | Previous naming | Upgrade `bob` for names |
| `task_link_count`, `max_task_link_count` | Auto-inserted `,` in `x`/link lists and `x=` lists | Older bob can assist `x`/link lists from the plain count; `x=` stays unassisted | Upgrade `bob` for `x=` assist |
| `relation_to` / `relation_from` completion | `~` / `~~` picker rows with replacements and intents | No rows; calm browse hint instead of a dry-run error | Upgrade `bob` for relations |
| `relation_label` completion and `relation` metadata | Relation card suggestions with counts, typed row, token range, direction, and owner | Without the metadata, the app uses its legacy token scan; without the completion context, no card opens | Upgrade `bob` for relation labels and exact token ranges |
| `relation_label` `key` / `inverse` / `hide_replacement` / `existing` / `hidden`, `hidden_count`, `one_off` | Canonical keys, inverse phrases, `||` insertions, typed validation flags, Hidden pill, one-off mode | Local label folding, no inverses, `|` insertions only, no Hidden section or pill, no one-off mode | Upgrade `bob` for the relation vocabulary |
| `bob relations list -f json`, `hide`, `unhide` on the `relation-label-pref` lane | Hidden section, ghost hide/unhide rows with ⌃D undo | No Hidden pill; Ctrl-D and Ctrl-H give the update hint | Upgrade `bob` to hide relation labels |
| `bob relations rename -f json` dry run on the `relation-rename-preview` lane, apply on `relation-label-pref` | Rename mode with live preview, merge confirm, draft fix-up from `label_range`s | Ctrl-R gives the update hint | Upgrade `bob` to rename relation labels |
| `relation_label_hides[]`, structured `hides_existing_relation_label` warning | Amber preview row, card warning, `· hid` notification suffix | No hide rows; structured warnings decode as text | Upgrade `bob` for one-off hides |
| `relation_grammar` | `~` parses with relation spans; capability warning stays hidden | Calm `predates ~ links` warning; first ⌘↩ only shows it | Upgrade `bob` for `~` |
| `relation_updates[]`, `linked_from_line_updates[]`, `minted_relation_block_ids[]`, `mirror_skipped[]` | 🪢 preview rows, managed-line suppression, separate notification counts | Legacy preview without relation rows; notifications omit relations | Upgrade `bob` for relation previews |
| `cancels_source`, `configured`, `relation_cancel`, span `cancels_source`, `relation_cancels[]`, `cancel_effect`, `relation_cancelled_source` | ⊘ cancels capsule, dimmed source, verdict slot, cancelled span tint, ⊘ preview rows, `Capture & cancel N task(s)` | No cue; ordinary relation labels and preview rows | Upgrade `bob` for cancel labels |
| `completes_source`, `relation_complete`, span `completes_source`, `relation_completes[]` (with nested `task_complete`), `complete_effect`, `relation_completed_source` | ✓ completes capsule, dimmed source, verdict slot, complete span tint, ✓ preview rows with `!` detail rows, `Capture & complete N task(s)` / `Capture & close N tasks`, in-panel successor choice | No cue; ordinary relation labels and preview rows, no successor offers | Upgrade `bob` for complete labels |
| Candidate/span `offers_source`, `relation_successor` in `capture-complete` | `link` / **offers** capsule and successor-label tint; show Bob's `message` verbatim, released `already_parked` / `already_closed` messages in amber, and muted `hint` | Missing flags are false; inverse hints may omit verdicts. Source never dims; the app never infers verdict from task status | Upgrade `bob` for successor-label authoring |
| `capture-related` | A settled Similar tasks band beneath matching task cards | Band stays hidden; ordinary preview and capture continue | Upgrade `bob` to show similar tasks |
| `wikilink_task_delimiter` / `wikilink_task_query` parse spans, `wikilink_task` / `wikilink_replacement` | Task Wikilink picker with link inserts | Older Bob emits no spans, so no completion; `((` stays plain text | Upgrade `bob` |
| `project_task_move` need, `project_task_move_marker` / `project_task_move_link_marker` / `project_task_move_block_id` spans, `project_task_move` completion context, `picker` (`kind: project_task_move` with `destination`, `continuation`, `action_continuation_aliases`), `project_task_move` header, row `consequence` / `scheduled` / `hidden` | Move picker: `Move into <dest>` header, sections, Bob consequence footer, Shift-Return chaining, Add ID, calm Escape status, new span colours | Older Bob omits the need, so behaviour is unchanged; without aliases, `.` filters | Upgrade `bob` for move bullets |
| `moved_tasks[]` / `move_summary` / `move_hint` on `project_note`, `moved_from` on offers | Moves band with repair footer, ghost titles, move hint, `moved from` label, `Created` notification | Band, ghosts, hint, and labels stay hidden; legacy copy remains | Upgrade `bob` for move previews |
| `record`, `--next-missing-field` / `--record-field` | Record drafts and `eat/` rows; old Bob omits or rejects | Stays a literal task | Upgrade `bob` |
| `note_files[]`, per-item `record_note`, refusal `draft` / `missing[]` / `invalid[]` | Record commit summary, exact `note_files` Markdown, and inline refusals; malformed rows degrade to generic preview | Generic preview and result copy | Upgrade `bob` for record result details |

The app waits 350 ms after an edit before requesting `capture-related`. An older `bob`
that rejects the command is remembered for that executable identity, so the app keeps
the band hidden without retrying on later drafts. Changing the executable identity
rechecks support.

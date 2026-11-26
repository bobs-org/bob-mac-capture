---
title: "Mac Capture protocol"
description: "Bob Mac Capture subprocess commands, JSON boundaries, capability requirements, and compatibility."
---

Bob owns grammar, completion, previews, and writes ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)).

Caret Go To uses `task_goto`, `goto`, and `block_id.goto`; older or unknown
responses render neutrally.

## Capability requirements

`bob` must support these contracts before the panel can use them:

- Whole-draft `//query` support: `capture-parse` reports `note_goto`; `capture-complete`
  returns the `note_goto` catalog metadata (`vault_root`, `listed`, `archived`), note
  candidates, and a `picker` descriptor with Bob's `trigger_removal_range`. Pass
  `--archived-notes` for the archive catalog (`archived: true`). A bare `/` `task_goto`
  response carries its descriptor and advertises `/` as the Notes continuation. The
  app opens the selected relative `note_path` only when Bob reports `note_goto`.
- A `bob` build that supports route-only `@@route` global destination declarations
  anywhere in the draft, `capture-rewrite` (including
  `switch_block_id_separator` for `^`, `:`, `+`, a glued `.`, and a glued `,`),
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
  `@route:block-id#name=<X>` suffix (`pomodoro_start` parse/capture JSON and
  span), plus whole-item `+[N]`/`-[N]` duration adjustments
  (`pomodoro_adjust` parse/capture JSON and span), plus whole-item
  `++[N]`/`--[N]` session shifts (`pomodoro_shift` parse/capture JSON and
  span), plus whole-item `=`/`=<X>` session starts (`pomodoro_start`
  parse/capture JSON and span, with the queued Task Links in the capture
  summary), plus whole-item `=<X>#name` named starts (the `pomodoro_name`
  span, the `pomodoro_start_name` completion context with the additive
  `next_up` row marker, the `=#` incomplete state with its
  `interactive_placeholder` span, `x#name` close near-miss diagnostics, and
  the additive `created_pomodoro` capture summary),
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
  `project_note.successors` with Pull-In keys. Picked rows enter
  `task_links`; count them once as Linked, never again as pulled-in successors.
  Either separator plus seal uses existing `project_note` completion intent;
  new intents would be misread as `link` by older Macs.
  Lists, bulk templates, and notebooks use the additive fields in the
  compatibility table. The app applies Bob's list splice and groups results
  by `list` ([Capture lists](capture-lists.md)); it never splits a draft or
  places an ID itself. Grammar 26 adds
  `notebook_section_bullet`, span `notebook` / `section_action`, and
  `place_menu` chrome for drawer and notebook section menus.
  Task Wikilink picks require `capture-parse` spans
  `wikilink_task_delimiter` / `wikilink_task_query` to request the `wikilink_task`
  completion context (with the additive `link_target` candidate field, Bob-order
  groups, and picker descriptor) and `wikilink_replacement` on `capture-task-id`
  results.
  Go To and Command-\ today-Pomodoro landing and Bob Refs Control-Return
  require bob-plugins **bob-navigation-hotkeys ≥ 2.32.0**.
  Control-Return landing via `obsidian://bob-open-notes` needs
  **bob-navigation-hotkeys ≥ 2.44.1**.
  Missing `pomodoro_start`/`pomodoro_close` omits its card; missing summary arrays
  decode empty, booleans false, unknown close roles neutral. A close without
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
  `*`/`!` group selects all numbered links left after explicit assignments
  (`x*1`, `x!1` narrow to task 1); two empty wildcard groups compete and
  need numbers on at least one group. One entry may sit on the close line
  itself (logging to task 1, or to the first eligible top-level worked link
  with wildcard intent): an explicit number adds a cyan
  `pomodoro_close_log_index` span while the default adds none, and a
  dangling inline number reports mode `incomplete` with a
  `pomodoro_close_log_text` need and an `interactive_placeholder` span.
  Further entries use ⌃J bullets with optional `  - …` detail lines, adding
  a `log` parse spec with the typed entries in order, each carrying its
  `details`. Bullets may omit the number: unnumbered bullets log in order
  to the close's worked tasks, and a single worked task takes them all.
  Bullets are numbered all or none, and a leading number is always a task
  number. Numbered entries add cyan `pomodoro_close_log_index` spans while
  positional entries get none; `capture-parse` omits `log[].index` for
  entries `bob capture` resolves against the running session, and the
  app decodes a missing index as nil. Entry and detail text keeps wikilink
  spans but is neutral prose, and a dangling bullet reports mode
  `incomplete` with a `pomodoro_close_log_text` need and an
  `interactive_placeholder` span instead of an error.
  Inline entries require a bob that understands them; an older bob reports
  `invalid_pomodoro_close` on the entry. An older Bob that omits `log`,
  `details`, `typed_work_log`, or `typed_work_log_details` decodes as
  without them, so the card shows only the capped `work_log` previews. A
  parked (`*<P>`) close records normal In Progress work without carrying
  those links forward; parked rows keep readable, unstruck, undimmed text
  with their transition, a `pause.circle` accent, and VoiceOver
  naming the hold. The summary groups `Continue`, `Parked`, `Complete`,
  `Deferred`, and `Dropped` in that order; `Continue` means
  worked links carried onward and never names a task status. A dropped
  (`~<K>`) close removes those links from today without carrying or
  starting them; the card strikes and dims dropped rows and adds a
  "stays <status>" caption naming the lane each task keeps. The
  `x*`/`x!` all-task selection behavior requires an updated
  Bob executable. With an older Bob, the app displays Bob's
  preview and submits the untouched draft through one Bob capture call; it
  never parses selection lists in Swift or simulates the new behavior. The
  app keeps schema-version rejection unchanged. A whole-item `=`/`=<X>`
  start reports the numbered lineup: per-row `index` in the capture
  summary, a `drop` list on the parse spec and capture summary, and removed
  rows in `dropped` with their `index`, pre-image `ledger_line`, and
  `nested_lines` count; a trailing `~<K>` adds a muted-gray
  `pomodoro_start_drop` span, and a dangling `~`/`,` reports mode
  `incomplete` with a `pomodoro_start_task` need and an
  `interactive_placeholder` span instead of an error. A start summary
  missing `drop`, `dropped`, `index`, or `nested_lines` still previews as
  an unnumbered card: no drop, no badges, and no drop hint or summary.
  `toggle_direction` is `link` or `unlink` with `status_changed` on every
  result: linking shows the added link with `set Next`, `stays Next`, or
  `stays In Progress`, and unlinking shows the removed-link count with
  `stays <status>`. Older Bob builds that send `next`/`open` still decode to
  the same Set Next/Open footers. The app labels
  actions and notifications from Bob's behavior metadata; a response
  that omits `toggle_behavior` still shows the two-way Set Next/Open footer,
  never Ensure Next. Captures that change today's `## Pomodoros` section
  report a top-level `plan_budget` object with a before/after link meter and
  link-cap warnings that fire only while the batch grows the meter past its cap;
  the same destination carries a `role` of `current`, `next_up`, `named`, or
  `created`. The daily plan caps Task Links only, so the app shows no type
  meter, delta, or type-cap badge or hint; an older Bob's `themes` meter,
  `added_themes`, `plan_themes_after`/`plan_themes_cap`, `plan_theme_cap_exceeded`
  warnings, and refusals are decoded as absent or ignored. `plan_budget`
  carries `added_theme_refs`, the hue refs for the added names: created
  destination, start, toggle, and project-note rows wear theme pills.
  `pomodoro_name` and `task_toggle_pomodoro_name` spans, agenda entries,
  and Refs Today rows carry `themes` refs for the same tints; unknown and
  exempt names stay neutral and home dots are untouched. The shared
  catalog, hue, and menu rules are defined in the [Pomodoro themes
  contract](https://bobs-org.github.io/pomodoro-themes/). An older Bob
  that omits `plan_budget`, `role`, `added_theme_refs`, span or entry
  `themes`, or `code` still previews and captures; the Mac app decodes each
  as absent and renders the destination row as `→ NAME`, omitting the
  TODAY badge and theme tints. A trailing `#now` tag is a trailing-tag error; `#now`
  before the route is plain body text. The `^` picker lists In Progress and
  Next tasks only. An older Bob that sends the `now` flag, `now_tag`
  span or context, or `now` group still previews and captures; the app
  decodes unknown spans neutrally, unknown contexts as generic rows, and
  unknown groups as `note`. Saving links to the reading queue needs a Bob that
  emits the `ref` capture kind with the additive `ref` object, `ref` parse
  mode, and the `ref_url` span. An older Bob keeps capturing a bare link as
  an inbox task. Filing a link needs a Bob that resolves the
  canonical parent: the additive `ref.parent` object (`route`, `label`,
  `kind`, `source`, `alias`) on capture results, `ref_parent` (`token`,
  `source`) on `capture-parse` `ref` items, and `project_name_aliases` on
  `capture-targets` entries. A bare URL queueing under the default parent
  opens the route list on its own with the header **File under**: cached
  inbox, area, and project targets with the last-used parent first, then
  `mac_inbox`; typing filters with aliases included, and route completion
  ranks alias matches after prefix route matches. Accepting inserts
  ` @<route>`; Esc keeps the default and the list does not reopen until
  the URL changes. Library hits never open it. The last-used parent is
  remembered after a successful submit. An older Bob that omits `ref.parent`,
  `ref_parent`, or `project_name_aliases` still previews and captures; the
  Mac app decodes each as absent, keeps today's wording, never auto-opens
  File under, and matches routes without aliases, so upgrade Bob before
  filing links. Inbox routing needs a Bob reporting the additive `inbox_route` object on every
  capture JSON and accepting `--inbox-route KEY=<relative_path>` (or `KEY=` to
  keep) plus the hidden `--require-inbox-route-choice` guard; without it the app
  captures without asking.

Grammar 12 adds past-work `x=` recording (`pomodoro_past` mode, spans,
  summaries, windows, trims, warnings), decoded tolerantly with no synthesized
  top-level close.

Grammar 14 segment suffixes precede `!` / `=`: `~` tail, `~N` / `~N+`
segment start/end, `~~` head. Bob returns spans, candidates, resolved segment/pin,
and cuts. Segment-ending `-` rewrites to `~`; stale-window guards refresh previews.

The app never uses a login shell to find `bob`; a Settings override must be an
absolute path (see [Install](install.md#requirements)).

## Move-choice submission

`move_choice.supported` gates `--move-in KEY,:KEY|none`, sent before `--pull-in`.
[Move-card protocol](task-pickers.md#move-card-protocol) documents slots, refusals,
answer chaining, and optional decoding.

## Mail-close submission

Dry-run JSON may carry `mail_close`; `Y` resubmits with `--mail-close`. Older
  Bob omits it.

## Successor verdict and jump submission

`pull_in.close.supported` gates `--complete-offer`/`--cancel-offer`;
`pull_in.jump.supported` gates `--jump-offer`. Pin-only commits send
`--pull-in none`. Bob re-finds `jump.landing` after writes, or returns `null`.
Refusals reopen intact; stale picks refresh once without writing; lost pins clear.
See [Move-card protocol](task-pickers.md#move-card-protocol).

`copy.glyph: "requirement"` or `group: "requirements"` selects requirement marks,
including legacy text glyphs. Row `run` stays an opaque fallback; marks follow
staged verdicts.

Same-executable preview capability `pull_in.reqs.supported` gates
`--req-choice`; legacy Bob receives no flag and staged keys never retry as
ordinary capture. Requirement-only groups open the card; default Met commits.
Show `req_outcomes` once. Bob's [requirement-close contract](https://bobs-org.github.io/task-dependencies/#1225-requirements-on-the-successor-card)
defines flags, refusals, and vectors.

## Timeouts and guards

Every `bob` call times out in 20 seconds; quit cancels outstanding calls.

Known guard refusals retry once per executable: `--refuse-override` and
`ref scan -a` / `--attended` retry without the rejected flag on exit 2.
`--require-pull-in-choice` and `--require-inbox-route-choice` require support
in the matching preview and never retry. Other failures never retry; offer keys
come only from matching previews or write-free refusals.

`--template-origin` requires that executable's successful template-list; see [Saved templates](saved-templates.md).

## Required commands

Required commands must exist; otherwise their feature hides or Bob refuses:

- `capture-parse --format json` (spans, needs, replacements, ranges, `cursor_after`; records add `record`)
- `capture-complete --all-tasks [--closed-tasks] [--next-missing-field] [--record-field KEY] --cursor BYTE --format json` (candidates; records add `record` and `continuation`)
- `capture-rewrite --cursor BYTE --format json` (marker and separator rewrites, relation-label attachment, sigil aliases including item-start/spaced `.` → `@`/`&` and `;` → `:`/`*`, template start)
- `capture --dry-run [--no-clip] --format json` (live preview; `--no-clip` omitted unless the accepted parse has a `%c` span) and `capture --format json` (submit)
- `capture-pomodoros --format json --tasks` (agenda, counts, landing, `max_task_link_count`); plain `capture-pomodoros` reports the bound and supplies the running count for older-bob fallback
- `capture-task-id` / `capture-pomodoro-name` (Add block ID / Name Pomodoro prompts)
- `capture-targets` (route list), `capture-templates list` / `save` (template shelf)
- `ref list -R all -A -f json` (Refs snapshot, schema 1; add `-g` while any row lacks an `added` date or git instant)
- `plan -f json` (Refs Today join, schema 2)
- `ref scan -a -w -f json` (Refs scan report, schema 1; `-a` retries without the flag per executable)
- `ref show <note-path> -f json` (inspector hydration)
- `ref rename` (Rename card)
- `vault-sync -q` (Refs pull on panel show and before ⌘R)

Bob Refs ⌘S and the enabled Highlights-save trigger use this scan command; the receipt path and notification are in [Bob Refs](refs.md).

## Optional commands

Optional commands stay hidden when absent:

- `capture-related --format json -- DRAFT` (settled similar-task matches and draft anchors, schema 1)
- `gcal note` JSON: list/show/preview/save/clear; [Event notes](event-notes.md)
- `walks --format json` (s/w/b title-row attention, schema 1)
- `snooze wake -q -f json` (schema 1; `woke`, `nothing_due`, `deferred`, `skipped`;
  `deferred`/`skipped` postimages never settle; absent support disables waking
  until Recheck Bob or executable replacement)

## Optional fields

Absent fields decode tolerantly and only hide their own row, badge, or offer:

- `creates_pomodoro`, `pomodoro_start`, `pomodoro_adjust`, `pomodoro_shift`, `pomodoro_close` (plus `log`, `details`, `typed_work_log`, `typed_work_log_details`)
- `pomodoro_start.override`, `toggle_behavior`, `toggle_direction` with `status_changed`
- `plan_budget`, destination `role`, `code`, `added_theme_refs`
- span `themes` (`pomodoro_name`, `task_toggle_pomodoro_name`, `task_type`), agenda entry `themes`, Refs Today row `themes`
- `task_type` completion context, top-level `subject` (`new`/`existing`), candidate `current` / `inherited` / `effect` / `refused`
- `task_theme.action` `kept`, `type_relocation` (`outcome`, `from`, `to`)
- `configured` on theme refs and `themes list` rows, `configured_themes`, `hue_source`, and `theme_not_configured` warnings on capture and `capture-pomodoro-name`
- `ref` with `ref.parent`, `ref_parent`, `project_name_aliases`
- Refs list fields `blocked`, `task`, `added_at`; snapshot cache key `git_added_at`; copy-card `marker_id`
- Scan report fields `generated_at`, `summary.held`, `held[]`, `notes[].marker_write` (`mode`, `editor_saved_first`, `status.from`/`to`)
- `block_id` object, `picker` descriptor, `parent_replacement`, Parent Task continuation metadata, `pomodoro_start_name` context
- `wikilink_task` `link_target`, `wikilink_replacement`
- `open_notes`, `homes`, `task_links`, successor-offer payloads
- `headline`, snoozed agenda rows and wake provenance; `snooze` span tint
- `walks` `counts` (s=`walk`, legacy fallback=`commitments`; w=`excess`; b=`waiting`), `tier`/`label`/`reason`; unknown families ignored
- `inbox_route` (candidates, destinations, `repaired_files`, `renamed_block_ids`, `needs_reconcile`) and `refused` detail on `inbox_route_refused`
- `mail_close` on success
- `notebook` summary (`route`, `title`, `breadcrumb`, `section`, `section_action`, `block_id`, `parent_block_id`); target/completion notebook display metadata
- `place_menu` chrome; notebook section candidates (`group`, `detail`, `refused`, `consequence`, `creates`, `cursor_after`); span `notebook` / `section_action` / `title`
- `relation_grammar`, relation-label `relation` token metadata and `owner`, `relation_updates`, `linked_from_line_updates`, `minted_relation_block_ids`, `mirror_skipped`, relation-label `count` / `typed`
- dependency/plain-link ties: `dependency_tie` (+ deprecated `also_prerequisite`), `plain_link`, `subsumed_by`, per-item `absorbed_plain_links[]`, `dependency_and_plain_link` refusal
- relation vocabulary: label `key` / `inverse` / `hide_replacement` / `existing` / `hidden`, `hidden_count`, `one_off`, `bob relations list` / `hide` / `unhide`, `relation_label_hides[]`, structured capture warnings, `bob relations rename` preview/write with counts, `label_range` / `hidden` on `relations[]`
- Past fields: segment/pin, windows/cut, candidate bounds/repair, stale refusal
- Record: `record`, `continuation`, `type`/`emoji`/`count`
- Retired `now` inputs (flag, span, context, group) decode as neutral rows

## Compatibility

| Feature or field | Expectation | When absent | Reader action |
| --- | --- | --- | --- |
| `@@route` declaration | Unmarked items route to the declaration; items retain their own route overrides | Ordinary draft capture; bare markers report Bob's local error or an empty list | Upgrade `bob` for declarations |
| `capture-rewrite`, `switch_block_id_separator`, `attach_relation_label`, `expand_sigil_alias`, `toggle_relation_direction` | Rewrites markers, relations, `.` → `@`/`&`, `;` → `:`/`*`, Parent Task commas, and `x`/`s` outcomes | Older Bob leaves every `.`/`,` literal, including item-start `.` (no new gate); old apps lack fast modifier escapes/restores | Upgrade `bob` |
| `project_note` span modifier, `project_note_separator` and `project_note_offer_marker` spans, the `@` seal | Chip behind the sealed marker (brown name/seal; green `:`/`@` on offers) | Older Bob omits the modifier; an older app shows a yellow seal and neutral separator, without wash | Upgrade `bob` for the chip; upgrade the app to paint it |
| `capture-complete --all-tasks` | Full candidate lists | Empty list or local error | Upgrade `bob` |
| `--closed-tasks` in Go To | Command-X switches to closed rows | Older Bob keeps open rows and shows the update hint | Upgrade `bob` |
| `--archived-notes` in Go To Notes | Command-X switches to archived notes (`note_goto.archived`) | Older Bob keeps living notes and shows the update hint | Upgrade `bob` |
| `task_link` / `task_goto` / `task_parent` / `task_block_id` contexts | Picker rows with replacements and intents | No rows; calm browse hint instead of a dry-run error | Upgrade `bob` |
| `note_goto` context, `note_goto` object (`vault_root`, `listed`, `archived`), and `note_goto` picker descriptor | Go To Notes catalog, grouped rows, Archive scope, and Bob-authored `//` peel range | No Notes picker; `/` stays Go To · Tasks, which asks for an updated Bob when the slash continuation is missing | Upgrade `bob` |
| `task_goto` picker descriptor with `/` continuation | Empty-filter `/` opens Go To Notes | Slash is consumed and the picker says **Update bob to search notes** | Upgrade `bob` |
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
| Grammar 26 `notebook_section_bullet`, notebook `section` completion, `place_menu` | Notebook section menus for glued `@route#` and first-level bullets, using Bob's chrome | Older Bob: ordinary section completion and the legacy drawer menu | Upgrade `bob` for notebook section menus |
| `grammar` ≥ 5 on `capture-parse` | Capture with whole-item `=/` split and `=*` merge syntax, along with earlier capture grammar | Capture disabled; "Update bob to use Pomodoro split and merge syntax"; the draft stays | Upgrade `bob` for split and merge |
| `grammar` 12 / 14, `pomodoro_past` / `pomodoro_past_segment`, `--expect-past-windows` / `pomodoro_past_windows_changed` | Past stacks/windows/trims; segment picker/card; stale preview refresh | Older Bob omits past cards and the stale guard | Upgrade `bob` for past segments |
| `pomodoro_split` / `pomodoro_merge` spans, modes, and summaries | Split/merge previews show before/after names, created/absorbed entries, and destination | Older Bob omits previews; these tokens do not parse | Upgrade `bob` for split and merge |
| `source_role`, `absorbed[].role`, and `explicit` on `pomodoro_merge` | Implied-pick **Current** / **Next** capsules and the `Same as` caption | Older bob omits them and the card renders as before | Upgrade `bob` for implied-merge captions |
| `pomodoro_split_type` / `pomodoro_merge_dest` needs and completion contexts | Bob's candidates drive the type and destination pickers | No picker rows; the incomplete draft stays visible | Upgrade `bob` for split and merge pickers |
| `drawer` completion context, `target`, candidate `group` / `detail` / `entry_count` / `note_count` / `last_seen` / `creates` / `refused` / `consequence` | New drawer in This task/Recent groups; Bob's counts; refused rows dim and no-op on Return; selected-row consequence footer | Older Bob lacks the context (requires grammar 5); without `detail`, hide counts; without `consequence`, keep the key hint | Upgrade `bob` for the full menu |
| `req: {depth, state}` on preview block lines and agenda `items[].lines[]` | One teal requirement mark from Bob's state; indentation carries depth | Missing or malformed objects use ordinary rendering; unknown state strings use pending | Upgrade `bob` for requirement marks |
| `drawer` object and preview annotation | Capsule, summaries, `tray` keep titles | Older Bob omits them | Upgrade `bob` for drawers |
| Grammar 30 spans, `expand_drawer_marker` | Semibold titles, dim delimiters, true-case writes | Older Bob uses ALL-CAPS | Upgrade `bob` for true-case drawers |
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
| `headline`, `snoozed`, `woke_at` / `snoozed_target`, `snooze` | Headline row; Later today band with woken accents; `z:` schedule tint | Neither row nor band; neutral `z:` | Upgrade `bob` |
| `bob walks` | s/w/b title-row marks | No marks, nothing else changes | Upgrade `bob` |
| `--tasks` on `capture-pomodoros` | Agenda, counts, `=name` names | Agenda hidden; counts from plain output | Upgrade `bob`, then Recheck |
| `pomodoro_start_name` | Start list for `=name` | No rows | Upgrade `bob` |
| Template spans, `%t` | Template rows, shelf, preview capsule | Ordinary drafts keep working; `%t` may be refused before writing | Upgrade `bob` for templates |
| `override`, guard flags | Orange banner; guarded commit; choice card | Plain start; retry without the flag is remembered | Upgrade `bob` for overrides |
| `pomodoro_blocks`, `task_blocks` | Full block views below the stack | Standard item stack | Upgrade `bob` for blocks |
| `task_complete.unblocked`, `pomodoro_close.unblocked`, `project_note.successors` | Grouped Pull-In choice card; project offers show a New project context and task preview rows | Single legacy wording | Upgrade `bob` for offers |
| `task_complete.keep_moving`, `pomodoro_close.keep_moving` | ⏭ Keep-moving section with the last-planned caption, ready-task lanes, folded reasons, choice keys, and `forward.end.fill` block-diff badge; notifications name the project | Missing arrays decode empty; existing successor offers keep working | Upgrade `bob` for keep-moving offers |
| `relation_successors`, `relation_held`, `relation_check` on capture items, task completion, Pomodoro close, and nested completions; row `relation` `{label,key,event,after}` and `offer.after` | Relation rows join ordered Pull-In groups; held/check notices are passive; counts and notifications reflect relations. Held: `waits_on`, `waits_for`, `scheduled`, `project`; checks: `checked` or `unavailable` | Missing arrays decode empty; absent check state is silent; malformed metadata drops while the row remains | Upgrade `bob` for relation successors |
| `pull_in.copy` `{title,capsule,glyph}`, group `copy` `{title,why,tag,fold,glyph}`, `after`, `label`, `event`, and `folded.already_started` / `waits_for` | Bob supplies chooser title, capsule, reason, tag, fold, glyph, relation target identity, and folded-reason line | Missing copy uses legacy per-group Swift wording/order; missing group metadata or fold counts adds no copy | Upgrade `bob` for Bob-authored Pull-In copy |
| Block-diff `reason: relation`, task-block role `relation_successor` | A `link` badge with “Offered by your relation link” help, and relation-successor task styling | Unknown reasons and roles keep their existing neutral fallback | Upgrade `bob` for relation block cues |
| Inbox routing | Route card before submit | Captures without asking | Upgrade `bob` |
| `mail_close` | Banner and card | No card | Upgrade `bob` |
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
| `dependency_tie` / `plain_link`, `subsumed_by`, `absorbed_plain_links[]` | Tie capsules, subsumed rows that count as no link, absorbed rows under ⛓ / 🧱 rows | Untied capsules, no tie or absorbed rows | Upgrade `bob` for ties |
| `cancels_source`, `configured`, `relation_cancel`, span `cancels_source`, `relation_cancels[]`, `cancel_effect`, `relation_cancelled_source` | ⊘ cancels capsule, dimmed source, verdict slot, cancelled span tint, ⊘ preview rows, `Capture & cancel N task(s)` | No cue; ordinary relation labels and preview rows | Upgrade `bob` for cancel labels |
| `completes_source`, `relation_complete`, span `completes_source`, `relation_completes[]`, `complete_effect`, `relation_completed_source` | ✓ completes capsule, dimmed source, verdict slot, complete span tint, ✓ preview rows, `Capture & complete N task(s)` / `Capture & close N tasks`, in-panel successor choice | No cue; ordinary labels and preview rows, no successor offers | Upgrade `bob` for complete labels |
| Candidate/span `offers_source`, `relation_successor` in `capture-complete` | `link` / **offers** capsule and successor-label tint; Bob's `message` verbatim, released `already_parked` / `already_closed` in amber, muted `hint` | Missing flags are false; inverse hints may omit verdicts; the app never infers verdicts | Upgrade `bob` for successor-label authoring |
| `gcal note` schema 1 | [Event notes](event-notes.md) | Missing command hides menu; Command-E explains upgrade; missing reasons omit rail labels; schema mismatch refuses | Upgrade `bob` |
| `capture-related` | Settled Similar tasks band beneath matching cards | Band stays hidden; preview and capture continue | Upgrade `bob` to show similar tasks |
| `wikilink_task_delimiter` / `wikilink_task_query` parse spans, `wikilink_task` / `wikilink_replacement` | Task Wikilink picker with link inserts | Older Bob emits no spans, so no completion | Upgrade `bob` |
| `project_task_move` need, `project_task_move_marker` / `project_task_move_link_marker` / `project_task_move_block_id` spans, `project_task_move` completion context, `picker` (`kind: project_task_move`), `project_task_move` header, row `consequence` / `scheduled` / `hidden` | Move picker with Bob consequence footer, Shift-Return chaining, Add ID, calm Escape status | Older Bob omits the need, so behaviour is unchanged; without aliases, `.` filters | Upgrade `bob` for move bullets |
| `moved_tasks[]` / `move_summary` / `move_hint` on `project_note`, `moved_from` on offers | Moves band with repair footer, ghost titles, move hint, `moved from` label, `Created` notification | Band, ghosts, hint, and labels stay hidden; legacy copy remains | Upgrade `bob` for move previews |
| `record`, `--next-missing-field` / `--record-field` | Record drafts and `eat/` rows; old Bob omits or rejects | Stays a literal task | Upgrade `bob` |
| `note_files[]`, per-item `record_note`, refusal `draft` / `missing[]` / `invalid[]` | Record commit summary, exact `note_files` Markdown, and inline refusals; malformed rows degrade to generic preview | Generic preview and result copy | Upgrade `bob` for record result details |
| Notebook `capture-targets` and route fields, `item_kind: "note"`, `destination_kind: "notebook"`, per-item `notebook`, and notebook `note_files[]` | Notebook route and parent rows, safe notebook ID copy, note previews, and exact create Markdown | Missing optional metadata decodes away; ordinary capture remains usable | Upgrade `bob` for notebook-specific display |
| Album `title` / `summary` / `owner` / `breadcrumb` on record `capture-targets` and route rows, per-item `album` on `record` / `record_note` / `note_files[]`, and the `album_holds_no_tasks` rewrite | Album-named record route rows, album destinations on record previews and success copy, and the one-key `@stem/` footer fix | Rows, headlines, and captions keep the legacy route/path layout; the refusal stays a plain status message | Upgrade `bob` for album display |
| Explicit unknown block-ID `intent` | Opens the New ID composer without showing task-link candidates | Missing intent keeps the legacy Link behavior | The app treats unrecognized intent values as unsupported |

`capture-related` waits 350 ms; an older bob is remembered per executable identity.

## Meeting notes

`bob ref meet` owns matching, hashing, and vault writes. The app passes one
opaque EVENT argv and `-c`; it never parses notes. Sheet keys and receipts:
[Meeting notes](meeting-notes.md).

Commands: `ref meet -l -f json`; `ref meet [EVENT] -c -d -f json`; `ref meet
EVENT -c -f json --expect-sha256 HEX`. Optional `--parent NOTE`, `--status
next|ready|wip|read`, `--overwrite`. Omit status so Bob's default wins. File
only `would_file` with `meeting.ref` and `notes.sha256`. Schema 1; null list
`ref`/`block_id`/`root`; `candidates[]`, `parent_candidates[]`, `existing`.
Exit-2 JSON choices decode; other failures and schema ≠ 1 error. Filed vs
queued stay distinct; queued means `bob ref scan`. Exit 2 `unrecognized
subcommand 'meet'` caches unsupported per executable; Recheck Bob or a new
identity probes again.

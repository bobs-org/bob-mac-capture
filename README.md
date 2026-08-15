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
- A `bob` build that supports `capture-complete --all-tasks` and
  `capture-task-id`. Older builds can still capture ordinary drafts, but the Add block
  ID flow reports the local Bob error until Bob is upgraded.

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

Ad-hoc signatures are useful for local development, but notification permissions and
launch-at-login trust are tied to the installed signed bundle. Reinstalling with a new
or expired certificate can require reauthorizing those system permissions.

## Runtime Contract

- Bundle identifier: `org.bobs.bob-mac-capture`.
- App type: `LSUIElement` resident menu-bar app.
- The `Bob` status-item menu offers Capture, Settings, Recheck Bob, Restart Bob Mac
  Capture, and Quit Bob Mac Capture, in that order. Restart discards an unsent draft and
  clears the canceled-draft stash exactly as Quit does — there is no confirmation dialog
  — and it refuses to quit (reporting a failure instead) when the running process is not
  launched from an installed `.app` bundle or that bundle no longer exists on disk. See
  "Updating, Reinstalling, and Rollback" below for what Restart is for.
- Production hotkey (the default): Control-Shift-Command-I.
- Development/rollback hotkey: Control-Shift-Command-O, selectable in Settings.
- The hotkey path uses a pre-warmed non-activating `NSPanel`; subprocess work is kept
  off that path.
- A fresh popup is a compact, Spotlight-like bar — a one-line editor plus persistent
  footer actions, no empty preview placeholder, no dead space. Its first frame uses a
  conservative compact fallback only until SwiftUI reports rendered editor, auxiliary,
  and footer metrics. After that, the window's height tracks measured content as the
  editor grows, the completion list appears, the live preview arrives, and errors show
  or clear, staying anchored at the window's top edge and clamped inside the screen's
  visible frame. Resizing is instant and unanimated so the content and window never
  desynchronize. Height is content-owned and not user-draggable; width remains
  user-resizable and reflows the editor, which is the one case that legitimately changes
  the content height. Completion, destination, preview, and error details live in the
  auxiliary overflow region; if the clamp binds (a very small display, very large dynamic
  type, an unusually long error), that middle region scrolls while the editor and primary
  controls stay visible.
- `CaptureCore` imports only Foundation and runs `bob` directly through `Process` with
  argv arrays and an explicit GUI-safe environment.
- Editor highlighting is derived from `bob capture-parse --format json` spans. The app
  validates UTF-8 byte ranges and ignores a malformed span set instead of applying a
  partial grammar view. Every span kind — capture markers and the five Obsidian wikilink
  kinds (`wikilink_delimiter`, `wikilink_target`, `wikilink_heading`, `wikilink_block_id`,
  `wikilink_alias`) — resolves through the single palette in `CaptureEditorPalette`, so
  the editor and the completion list never disagree about what color represents what
  syntax.
- Inline completion calls
  `bob capture-complete --all-tasks --cursor BYTE --format json -- <draft>`; accepted
  ordinary candidates apply the server-provided byte replacement range and
  `cursor_after` exactly, restoring a collapsed caret at that offset. Route completion
  also covers the route side of Bob's `@route^block-id` ordinary task-with-ID marker;
  the authored ID side has no existing-task picker and an empty completion result is
  shown as no list.
  For blank-line-separated drafts, completion still sends the complete draft as one argv
  value; Bob scopes the answer to the item containing the UTF-8 cursor and returns
  replacement ranges in draft-global byte offsets. See "Wikilink Completion" below for
  the Obsidian-specific contract and row presentation.
- In the `@route+` task context, Bob may return open tasks that still lack block IDs.
  Ready tasks stay first and insert in one action. Missing-ID rows replace the completion
  list with an inline **Add block ID** prompt; the draft remains unchanged while the app
  calls `bob capture-task-id --route ROUTE --task-ref REF --block-id ID --format json`.
  Only a confirmed Bob success splices the returned canonical ID into the saved
  replacement range and reruns preview. Cancel and every error keep the draft unchanged.
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
  authored-child depths.
- `bob capture --format json` keeps the legacy top-level first result for a single
  capture or compatibility fallback, and may add an ordered `captures` array for a batch.
  The app normalizes both shapes to one collection before updating preview, status,
  VoiceOver announcements, and Command-Return opening; it never splits a draft into
  multiple mutating `bob` subprocesses.
- Preview shows every block Bob will write, in Bob's own order: each item's parent
  `task_line`, authored children, then `clip.lines` and `schedule_log.lines` when the
  response carries them. One item stays compact; a batch renders an ordered stack with
  item count, destination/kind metadata, dividers, and exact `previewBlockLines`. The
  outer auxiliary detail region owns scrolling, so preview itself never nests another
  scroll view. Continuous live preview passes `--no-clip`, so it has no `clip` to show;
  the explicit **Preview** button and **Capture** resolve the clipboard and therefore
  mirror the full block.
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
  nonempty draft for this app session before clearing and closing.
- Canceled drafts live in a bounded in-memory stash for the lifetime of the running app.
  Settings persists only the capacity, defaults it to 10, and clamps it to 0...36. Zero
  turns the feature off and clears the in-memory stash. Capacity reductions keep the
  newest entries and drop older overflow. Repeated cancellations are retained as
  separate entries, even when their text is identical. Settings also shows the retained
  count and a confirmed **Clear Stash...** action.

## Keyboard

| Key | In the editor | While completion is visible | While Add block ID is open |
| --- | --- | --- | --- |
| Return | Capture, then close the panel | Accept the selected completion | Add the ID and select the task |
| Command-Return | Capture, open the target in Obsidian, then close the panel | Accept, then submit | Consume the key; do not capture |
| Shift-Return / Option-Return | Insert a newline | Insert a newline | Add the ID and select the task |
| Ctrl-J | Insert a new indentation-aware `- ` row, or turn a marker-only placeholder into a blank item separator | Same edit, and close completion | Native text-field behavior |
| Ctrl-U | Delete from the caret to the beginning of the current physical line | Delete to the beginning of the current physical line and close completion | Native text-field behavior |
| Command-V | Insert the clipboard's plain text, discarding source formatting | Insert the clipboard's plain text and close completion | Native text-field paste |
| Backspace | Remove an unused `- ` row in one action (native Backspace everywhere else, and for every modified Backspace) | Remove an unused `- ` row in one action | Native text-field Backspace |
| Tab | Indent the current column-zero continuation bullet to two spaces (normal focus traversal otherwise) | Accept the selected completion | Consume the key; do not indent or capture |
| Shift-Tab | Outdent the current two-space continuation bullet to column zero (normal reverse focus traversal otherwise) | Same outdent, then close completion | Consume the key; do not outdent or capture |
| Down / Ctrl-N | (normal focus traversal) | Select the next completion | Consume the key; do not move completion selection |
| Up / Ctrl-P | (normal focus traversal) | Select the previous completion | Consume the key; do not move completion selection |
| Escape / Ctrl-[ | Close the panel, retaining a nonempty draft without confirmation | Close completion | Cancel back to the task list |
| Control-S | Open the canceled-draft stash picker | Open the canceled-draft stash picker | Consume the key; finish or cancel the prompt first |
| Control-C | Stash a nonempty draft for this session, then clear and close | Stash a nonempty draft for this session, then clear and close | Stash a nonempty draft for this session, then clear and close |

Every capture action is reachable from the keyboard alone; the hotkey, editor, completion
list, Stash/Capture/Preview/Discard buttons, and stash picker never require a pointer. The editor
starts at one visual line, grows and shrinks with rendered content through six visual
lines, then scrolls internally for longer drafts.

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
**Shift-D Delete All**, immediately clears every retained canceled draft from the
current app session, closes the picker, leaves the panel open with an empty editor, and
reports only "Canceled draft stash cleared". Lowercase `d` does nothing destructive. The
Settings **Clear Stash...** action keeps its confirmation dialog for that non-modal
workflow.

| Key while stash is open | Behavior |
| --- | --- |
| 1...9, 0, A...C, -, E...Z | Restore that row immediately |
| Shift-D | Delete all retained canceled drafts for this app session |
| Return | Restore the selected row |
| Down / Ctrl-N | Select the next row, wrapping at the end |
| Up / Ctrl-P | Select the previous row, wrapping at the top |
| Escape / Ctrl-[ | Close only the stash picker |
| Control-S | Close the stash picker |

The 36-entry upper bound exists so every retained row always has a unique one-key
accelerator while reserving `D` for Delete All: `1` through `9`, then `0`, then `A`
through `C`, `-`, and `E` through `Z`.

A draft is one or more capture items separated by one or more blank or whitespace-only
physical lines. Within each item, the first nonblank line is the parent, followed by zero
or more authored `-`/`*`/`+` bullets. Column-zero bullets become first-level authored
children; bullets prefixed by exactly two ASCII spaces become nested authored children
under the nearest preceding first-level authored child. A marker (`@route`,
`@route+block-id` for an existing-task sub-bullet, `@route^block-id` for an ordinary task
with an authored block ID, `s:<N>`, `p:<N>`, `%`, …) at the end of any valid line
configures that item even when it appears on a child line. The app never parses that
punctuation itself: highlighting and completion follow bob-cli's semantic spans. Both
families complete their route side; only the `+` family's right-hand side offers
existing tasks, and the `^` family's authored ID has no picker. The retired
`@route::block-id` spelling is a parse diagnostic from `bob capture-parse`, not a
supported interactive form.

```text
Prepare the launch review
- Confirm the rollout owner
  - Send the owner the final date
- Attach the final checklist @work p:1
  - Verify the links

Write release note @notes#Ideas
```

Bob's routed marker syntax works directly in the editor. `@route^block-id` captures an
ordinary `[ ]` task with a trailing `^block-id` and no Pomodoro task link, while
`@route:block-id` keeps the Pomodoro-linked next-task behavior and `@route+block-id`
nests beneath an existing task. The app does not duplicate those grammar rules; it
colors the span kinds Bob reports, asks Bob for completion at the real caret, and submits
the original draft text.

Ctrl-J starts the next canonical `- ` row from anywhere in the draft, copying exactly the
current authored row's supported indentation (zero or two ASCII spaces). On a line that
contains only optional whitespace plus one `-`, `*`, or `+` marker, Ctrl-J replaces the
placeholder with exactly one blank item separator and puts the caret at the beginning of
the following line, reusing an existing line terminator when one is already there.
To author a nested row, press Ctrl-J from an existing nested row, or press Ctrl-J for a
fresh top-level placeholder and then Tab before or after typing its body to indent it
under the preceding first-level bullet. Shift-Tab reverses that, returning a nested
bullet to column zero. Tab/Shift-Tab only move a continuation bullet between Bob's two
supported source prefixes, exactly two ASCII spaces, so pasted or hand-authored drafts
must still use that exact two-space indent; they stop at that ceiling and floor and leave
every other line untouched. Ctrl-U deletes from the caret to the beginning of the current
physical line. Backspace on an empty `- ` row removes it in one action instead of
requiring two ordinary backspaces. All five shortcuts act on the native text view
directly, so undo, IME composition, and accessibility behave exactly as they do for
any other edit, and Bob's live parse/preview remains the sole authority for whether the
resulting hierarchy is contextually valid.

Command-V intentionally reads only the clipboard's plain-text flavor. Source formatting
is discarded because Bob's capture grammar is plain text, and letting AppKit choose a
rich HTML/RTF flavor forced a synchronous WebKit HTML import that could cost seconds per
paste from browser content.

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
inserted (Note/Heading/Block, alongside Destination/Section/Parent Task rows), a
primary line with restrained emphasis on the part of the text that matched what you
typed, and a secondary line with the canonical vault-relative path plus small badges —
`Alias`, a heading level like `H2`, a short block preview, `^block-id`, or `Add ID`.
`@route+` task suggestions are grouped as **Ready to use** followed by **Needs block
ID**, preserving Bob's order inside each group. Long paths truncate from the middle,
keeping the filename intact rather than the leading directory. The selected row's
accent-tinted fill uses each result's own semantic color (matching the editor's
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
returns it. A batch is titled with the item count, summarizes task/note and destination
counts, and emits one ordered body line per captured item without substituting an
ellipsis for later entries. The only newly authorized notification body content is the
captured semantic text; failure notifications still carry only the bounded error
message.

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
the backup after the installed copy re-verifies. If any step after the swap fails, the
script automatically restores the previous app from that backup and exits non-zero — an
interrupted or failed update never leaves `~/Applications` (or `/Applications`) without a
working previous copy.

`just install` swaps the bundle on disk, but the already-running process keeps executing
the old code in memory until it is restarted or the user logs in again. Choose
`Bob → Restart Bob Mac Capture` from the menu bar to complete the update: it quits the
running process and relaunches from `~/Applications/Bob Mac Capture.app` (or
`/Applications`), which by then is the newly installed build. This is the last step of
the update, not a separate manual quit-and-relaunch.

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
```

This also removes the launch-at-login registration's target, though macOS may keep a
stale, non-functional Login Items entry until the next login — remove it manually from
System Settings → General → Login Items if it lingers. The app stores only non-sensitive
preferences (bob path, vault path, hotkey choice, and canceled-draft stash capacity) in
`UserDefaults` under the bundle identifier `org.bobs.bob-mac-capture`; it never writes
captured text to disk itself.

## Privacy

- Captured text lives only in the panel's in-memory draft and in the arguments passed
  directly to `bob`; it is never logged, written to `UserDefaults`, included in
  notification bodies, or emitted in a signpost or Diagnostics entry.
  `BobClientError.description` explicitly redacts the trailing draft argument from every
  command it echoes.
- Canceled drafts retained with Control-C live only in the app-lifetime in-memory stash.
  They are cleared by Quit, Restart, capacity zero, or Settings' **Clear Stash...**
  action, and are never written to `UserDefaults`, notifications, signposts, logs, or
  Diagnostics.
- Diagnostics and Recent Activity in Settings are metadata only — status strings like
  "Ready," "Hotkey conflict," or "Target cache stale," never note content.
- Signposts (see below) carry event names and durations for Instruments, not payloads.
- Wikilink note paths, aliases, heading text, and block previews are read locally by
  `bob` to build completion candidates and are held only in the in-memory completion
  response and the visible row content. They are never logged, written to
  `UserDefaults`, or included in a notification, signpost, or Diagnostics entry — the
  same guarantee the draft itself gets.
- `@route+` task completion metadata and a user-authored block ID are sent only to the
  local `bob` subprocess. The app never opens or rewrites Markdown notes directly; Bob
  performs the vault write through `capture-task-id`, and the app updates the draft only
  after Bob confirms success.

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
- **Target/route completion is empty or stale**: Diagnostics reports "Target cache stale"
  with the underlying scan error; fix the reported cause (for example, an unreadable
  vault path) and reopen the panel, which retries the refresh.
- **Adding a block ID fails**: duplicate IDs, stale task refs, terminal tasks, and file
  I/O errors are Bob errors. The Add block ID card keeps the selected task and typed ID
  visible so you can edit, retry, or press Escape to return to the refreshed task list.
  The draft is not expanded until Bob confirms the write.
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
completion, preview, submit, plain-text paste (`paste-plain-text`), and notification
scheduling, visible in Instruments' Points of Interest / os_signpost templates. These,
and the bounded Recent Activity list in Settings, are metadata-only by construction —
see Privacy above.

## CI

GitHub Actions runs on `macos-26` for pushes to `master` and pull requests. The workflow
checks Swift formatting, `swift build`, `swift test`, bundle assembly, `plutil -lint`,
signature verification, and the bundle identifier. It also launches the bundled app and
requires the `launch-complete` signpost to appear in the unified log before quitting it,
so a broken entry point (no delegate assigned, no menu bar item, no hotkey) fails CI
instead of shipping silently.

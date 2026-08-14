# Bob Mac Capture

Native macOS 26 menu-bar capture app for Bob. The app owns presentation, process
orchestration, the global hotkey, settings, launch at login, and packaging. `bob-cli`
remains the only implementation of capture grammar, preview, completion data, and vault
mutation.

## Requirements

- macOS 26 with Xcode 26 or newer.
- SwiftPM from the selected Xcode toolchain.
- A signed or ad-hoc signed `bob` executable available at one of:
  - `~/.cargo/bin/bob`
  - `~/bin/bob`
  - `/opt/homebrew/bin/bob`
  - `/usr/local/bin/bob`

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
- Production hotkey (the default): Control-Shift-Command-I.
- Development/rollback hotkey: Control-Shift-Command-O, selectable in Settings.
- The hotkey path uses a pre-warmed non-activating `NSPanel`; subprocess work is kept
  off that path.
- `CaptureCore` imports only Foundation and runs `bob` directly through `Process` with
  argv arrays and an explicit GUI-safe environment.
- Editor highlighting is derived from `bob capture-parse --format json` spans. The app
  validates UTF-8 byte ranges and ignores a malformed span set instead of applying a
  partial grammar view.
- Inline completion calls `bob capture-complete --cursor BYTE --format json -- <draft>`;
  accepted candidates apply the server-provided byte replacement range exactly.
- Live preview calls `bob capture --dry-run --no-clip --format json -- <draft>` through
  a dedicated process-client API that asserts `--no-clip`. `%` markers stay literal in
  continuous preview; clipboard-resolving preview is a separate explicit action.
- The preview path assigns a fixed `BOB_PRIORITY_ROLL_SEED` for the draft lifecycle so
  randomized `p:<N>` scheduled dates can be reused by submission and reset only after a
  successful capture or discard.
- Capture targets are cached at launch, refreshed when the panel opens, and invalidated
  by a coalesced FSEvents watcher. Watcher or refresh failures mark the cache stale
  without clearing the last good route list.
- Every `bob` invocation is bounded by a 20-second timeout (`BobProcessClient.defaultTimeout`)
  that terminates and reaps a wedged process instead of leaving the panel waiting
  indefinitely; a fired timeout surfaces as an actionable `BobClientError.timedOut`. Quit
  cancels every outstanding invocation via `cancelActiveProcess()`.

## Keyboard

| Key | In the editor | While completion is visible |
| --- | --- | --- |
| Return | Capture | Accept the selected completion |
| Command-Return | Capture and open the target in Obsidian | Accept, then submit |
| Shift-Return / Option-Return | Insert a newline | Insert a newline |
| Tab | (normal focus traversal) | Accept the selected completion |
| Down / Ctrl-N | (normal focus traversal) | Select the next completion |
| Up / Ctrl-P | (normal focus traversal) | Select the previous completion |
| Escape | Close completion, then close the panel (retaining a nonempty draft) | Close completion |

Every capture action is reachable from the keyboard alone; the hotkey, editor, completion
list, and Capture/Preview/Discard/Keep Draft buttons never require a pointer. Multi-line
drafts are an editing affordance only: embedded newlines are whitespace-normalized into a
single line by `bob capture`, matching its documented CLI contract.

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
makes capture correctness depend on them. Notification bodies omit captured text by
default. Settings shows live authorization status, a button to request authorization,
a link to the system notification settings pane, and a test-notification action.

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
preferences (bob path, vault path, hotkey choice) in `UserDefaults` under the bundle
identifier `org.bobs.bob-mac-capture`; it never writes captured text to disk itself.

## Privacy

- Captured text lives only in the panel's in-memory draft and in the arguments passed
  directly to `bob`; it is never logged, written to `UserDefaults`, included in
  notification bodies, or emitted in a signpost or Diagnostics entry.
  `BobClientError.description` explicitly redacts the trailing draft argument from every
  command it echoes.
- Diagnostics and Recent Activity in Settings are metadata only — status strings like
  "Ready," "Hotkey conflict," or "Target cache stale," never note content.
- Signposts (see below) carry event names and durations for Instruments, not payloads.

## Troubleshooting

- **"Bob is not resolved"**: Settings shows the resolved path (or "Not resolved") and the
  underlying error. Set an absolute path under "Executable override" or install `bob` at
  one of the default candidate locations, then use "Recheck Bob."
- **A `bob` command times out**: every `bob` invocation is bounded (20s by default); a
  wedged process is terminated automatically rather than leaving the panel stuck, and the
  resulting error names the timed-out command (never the captured text).
- **Notifications never appear**: confirm Settings → Notifications shows "Authorized," use
  "Send Test Notification," and check Diagnostics → Signing — notification delivery
  requires the installed signed bundle, not `swift run`. If authorization shows "Denied,"
  use "Open System Notification Settings" to re-enable it there.
- **Target/route completion is empty or stale**: Diagnostics reports "Target cache stale"
  with the underlying scan error; fix the reported cause (for example, an unreadable
  vault path) and reopen the panel, which retries the refresh.
- **Capture fails but the draft disappears**: this should never happen — failures always
  preserve the complete draft and destination. Use "Copy Diagnostic" next to the error to
  capture the exact `bob` error for a bug report.

## Diagnostics and Signposts

The app emits `os_signpost` intervals/events (subsystem `org.bobs.bob-mac-capture`,
category `capture`) around hotkey receipt, panel ordering, editor focus, parse,
completion, preview, submit, and notification scheduling, visible in Instruments'
Points of Interest / os_signpost templates. These, and the bounded Recent Activity list
in Settings, are metadata-only by construction — see Privacy above.

## CI

GitHub Actions runs on `macos-26` for pushes to `master` and pull requests. The workflow
checks Swift formatting, `swift build`, `swift test`, bundle assembly, `plutil -lint`,
signature verification, and the bundle identifier.

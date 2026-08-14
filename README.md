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
- Development hotkey: Control-Shift-Command-O.
- Production cutover hotkey preference: Control-Shift-Command-I.
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

## CI

GitHub Actions runs on `macos-26` for pushes to `master` and pull requests. The workflow
checks Swift formatting, `swift build`, `swift test`, bundle assembly, `plutil -lint`,
signature verification, and the bundle identifier.

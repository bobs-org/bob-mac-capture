---
title: "Mac Capture install"
description: "Platform requirements, source install, signing identity, updates, rollback, and uninstall for Bob Mac Capture."
---

Install a signed `Bob Mac Capture.app` bundle. Source builds (`swift run`, a raw `.build` binary, or `just bundle` with the ad-hoc identity `-`) are for development; notification permission, Accessibility grants, and launch-at-login trust attach to the installed signed identity. Contributor recipes live in [Build](https://bobs-org.github.io/develop/mac-capture/build/). Capture capability requirements live in [Protocol](protocol.md). Settings that affect install are in [Settings](settings.md); permission effects are in [Permissions](permissions.md).

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

  ```bash
  command -v swift; swift --version           # whatever is first on PATH
  ./Scripts/xcode-swift.sh --version           # what build/test/bundle actually use
  ```

  If the two differ, `./Scripts/xcode-swift.sh --version` fails, or `import XCTest`
  fails to compile, update or select matching Apple developer tools rather than
  migrating tests off XCTest:

  ```bash
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

The app never invokes a login shell to find `bob`. A Settings override must be an
absolute executable path.

Capability contracts for capture, completion, and Refs commands are in [Protocol](protocol.md). Point Settings › Bob › Executable override at an absolute `bob` path when the default search list does not match the install.

## Install from source

```bash
just format-lint
just build
just test
just bundle
```

On a host without Xcode, only CaptureCore, RefsCore, and refs-rank build; `just portable-check` lints every Swift file and builds and tests those targets, but cannot type-check the `BobMacCapture*` targets.

`just typecheck-tests` type-checks all test targets on a Mac with only Command Line Tools.

`just bundle` creates `.build/bundle/Bob Mac Capture.app` and signs it with the ad-hoc
identity `-`, which is the right default for agent scratch builds. `just install`
instead resolves its identity: an explicit `--identity` or `CODESIGN_IDENTITY` wins
(including `-`), otherwise it signs with the stable "Bob Mac Capture Local" identity
when the login keychain holds it, and falls back to ad-hoc with a loud warning:

```bash
just install ~/Applications
just install ~/Applications "Apple Development: Name (TEAMID)"
```

`just install` is the complete update for the selected target: it restarts that installed
copy if it was already running, and leaves it stopped otherwise. See
[Updating, reinstalling, and rollback](#updating-reinstalling-and-rollback).

Ad-hoc signatures are useful for local development, but notification permissions,
Accessibility grants, and launch-at-login trust are tied to the installed signed
bundle. Reinstalling with a new or expired certificate can require reauthorizing
those system permissions.

Signing, keychain, and identity recovery are in [Signing](#signing). The swap, restart, and rollback rules are in [Updating, reinstalling, and rollback](#updating-reinstalling-and-rollback).

## Signing

Bob Mac Capture needs an Accessibility grant to read Highlights tabs, and macOS ties
an ad-hoc app's grant to its exact `cdhash` — so every ad-hoc `just install`
silently revokes the grant while System Settings still shows it on. Signing every
install with one stable self-signed identity ("Bob Mac Capture Local") keeps the
grant across reinstalls. The first `just install` from a GUI Terminal creates this
identity automatically when it is missing; bob-cli's `just install-all` does the
same. Settings › References shows the grant as "Highlights tabs: Allowed / Not
allowed".

If automatic setup is unavailable, create the identity manually in Keychain Access:

1. Open Keychain Access and select the **login** keychain.
2. Choose Keychain Access › Certificate Assistant › Create a Certificate.
3. Name it exactly `Bob Mac Capture Local`.
4. Set Identity Type to **Self-Signed Root** and Certificate Type to **Code Signing**.
5. Give it a long validity period (ten years) and finish the assistant, storing the
   certificate in the login keychain.

On the first signed install, `codesign` prompts for keychain access: choose
**Always Allow** so future installs stay unattended.

Prefer a GUI Terminal or a tmux server started from one. Over SSH, or in a tmux server
first started over SSH, the login keychain is locked. While the identity is missing,
setup cannot run and the install falls back to ad-hoc. Once the identity exists, the
install checks before building that codesign can use it:

- **Locked session:** with a terminal, it offers `security unlock-keychain`. Otherwise
  it stops with exit 77.
- **Password mismatch:** after the Mac login password changes through `passwd`,
  `dscl . -passwd`, or `sysadminctl -resetPasswordFor`, the login keychain keeps the old
  password. loginwindow then fails to unlock it after every screen lock, and every app's
  keychain access fails. The install names this cause and offers a one-run unlock with
  the previous password. Otherwise it stops with exit 78. The lasting fix is
  `security set-keychain-password ~/Library/Keychains/login.keychain-db`. Changing the
  password in System Settings › Users & Groups keeps the two in sync.

`errSecInternalComponent` from codesign means it could not use the key in either case.
`just signing-check` runs the same check without building.

Verify an install with:

```bash
codesign -d -r- ~/Applications/"Bob Mac Capture.app"
```

A stable install shows `certificate leaf = H"…"`; an ad-hoc one shows a `cdhash`
designated requirement instead.

When an install changes the code signature, the installer clears the stale
Accessibility row. Grant the app again from Bob Refs › Tabs › Open Accessibility
Settings; later installs with the stable identity keep that grant.

## Updating, reinstalling, and rollback

```bash
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
`menu-bar icon → Restart Bob Mac Capture`: an unsent draft is discarded, retained canceled drafts
survive, and there is no confirmation dialog. The menu item remains the manual restart
mechanism when you want to relaunch without reinstalling.

When that automatic restart succeeds, the replacement process requests one
`Install complete` notification after `applicationDidFinishLaunching` finishes its normal
setup. Clicking the banner or `Capture` opens the capture panel; dismissing it does
nothing. The banner is best-effort: `just install` never prompts for notification
permission, and missing, denied, or reset authorization is silent and does not change
installer output, restart ordering, or whether the replacement launches. A stopped
install still does not launch or notify. `menu-bar icon → Restart Bob Mac Capture` does not show
the install-complete notification.

If the new bundle is installed and verified but the running-process handoff fails,
`just install` exits non-zero without rolling back that verified bundle. The error names
the installed path so you can start that copy, or use `menu-bar icon → Restart Bob Mac Capture` if
an old instance is still running.

To roll back deliberately, keep the previous release's commit or tag and rerun
`just bundle`/`just install` from that revision; there is no separate rollback command
because reinstalling the old build is the rollback.

To roll back the Hammerspoon cutover specifically, first turn off **Use production
Control-Shift-Command-I** in Settings so the app returns to Control-Shift-Command-R,
then restore the pre-cutover Hammerspoon files documented in the chezmoi repository.
Do not restore the old binding while the app still owns the production shortcut.

Reinstalling with a **different** signing identity (for example, moving from ad-hoc `-`
to a real Apple Development certificate, or renewing an expired certificate) resets
notification-authorization, Accessibility grants, and launch-at-login trust: macOS ties
all three to the exact code-signing identity, not just the bundle identifier. Expect to
re-approve notifications, re-grant Accessibility, and re-enable launch at login after
such a change, and prefer keeping one certificate for the lifetime of an install rather
than alternating between ad-hoc and signed builds. That is what the stable
"Bob Mac Capture Local" identity (see [Signing](#signing)) is for.

## Uninstalling

```bash
rm -rf ~/Applications/"Bob Mac Capture.app"   # or /Applications
rm -rf ~/Library/Application\ Support/org.bobs.bob-mac-capture
```

This also removes the launch-at-login registration's target, though macOS may keep a
stale, non-functional Login Items entry until the next login — remove it manually from
System Settings → General → Login Items if it lingers. The app stores only non-sensitive
preferences (bob path, vault path, hotkey choice, and canceled-draft stash capacity) in
`UserDefaults` under the bundle identifier `org.bobs.bob-mac-capture`. Canceled draft
text is stored separately in that Application Support directory (see [Permissions](permissions.md)).

Recovery steps for a missing menu-bar item or a failed restart are in [Recover a stuck Mac Capture panel](https://bobs-org.github.io/guides/recover-mac-capture/). Notification delivery is in [Restore Mac Capture permissions](https://bobs-org.github.io/guides/restore-mac-capture-permissions/).

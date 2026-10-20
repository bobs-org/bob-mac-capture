# Bob Mac Capture

Native macOS 26 menu-bar capture app for Bob. The app owns presentation, process
orchestration, the global hotkey, settings, launch at login, and packaging. `bob-cli`
remains the only implementation of capture grammar, preview, completion data, and vault
mutation.

## Docs →

- [Get started](https://bobs-org.github.io/start/mac-capture/)
- [Reference](https://bobs-org.github.io/reference/mac-capture/)
- [Develop](https://bobs-org.github.io/develop/mac-capture/)

The site is <https://bobs-org.github.io/>.

## Requirements

- macOS 26 with Command Line Tools for Xcode 26+ or Xcode 26+.
- A signed or ad-hoc signed `bob` executable at `~/.cargo/bin/bob`, `~/bin/bob`,
  `/opt/homebrew/bin/bob`, or `/usr/local/bin/bob`.
- A vault directory (`BOB_DIR`, default `~/bob`).

Toolchain selection, capability contracts, updates, and uninstall are in
[Install](https://bobs-org.github.io/reference/mac-capture/install/).

## Install

From a checkout of this repository:

```bash
just bundle
just install ~/Applications
```

`just bundle` writes `.build/bundle/Bob Mac Capture.app` and signs it ad-hoc.
`just install` signs with the stable `Bob Mac Capture Local` identity when the login
keychain holds it, creates that identity from a GUI Terminal when it is missing, and
restarts an already-running copy.

Point Settings › Bob at the `bob` you installed and your vault, then confirm:

```bash
which bob
echo "$BOB_DIR"
```

## Docs →

- [Get started](https://bobs-org.github.io/start/mac-capture/)
- [Mac Capture reference](https://bobs-org.github.io/reference/mac-capture/)
- [Mac Capture development](https://bobs-org.github.io/develop/mac-capture/)
- [Guides](https://bobs-org.github.io/guides/)

Major topics:

- [Install and signing](https://bobs-org.github.io/reference/mac-capture/install/)
- [Keyboard](https://bobs-org.github.io/reference/mac-capture/keyboard/)
- [Bob Refs](https://bobs-org.github.io/reference/mac-capture/refs/)
- [Protocol](https://bobs-org.github.io/reference/mac-capture/protocol/)
- [Build](https://bobs-org.github.io/develop/mac-capture/build/)
- [Fix Mac Capture when bob is not resolved](https://bobs-org.github.io/guides/fix-mac-capture-bob-resolution/)
- [Resolve a Mac Capture hotkey conflict](https://bobs-org.github.io/guides/resolve-mac-capture-hotkey-conflict/)
- [Restore Mac Capture permissions](https://bobs-org.github.io/guides/restore-mac-capture-permissions/)
- [Recover Bob Refs](https://bobs-org.github.io/guides/recover-bob-refs/)
- [Recover a stuck Mac Capture panel](https://bobs-org.github.io/guides/recover-mac-capture/)

The site is <https://bobs-org.github.io/>.

## Signing

Bob Mac Capture needs an Accessibility grant to read Highlights tabs, and macOS ties
an ad-hoc app's grant to its exact `cdhash` — so every ad-hoc `just install`
silently revokes the grant while System Settings still shows it on. Signing every
install with one stable self-signed identity (`Bob Mac Capture Local`) keeps the
grant across reinstalls. The first `just install` from a GUI Terminal creates this
identity automatically when it is missing; bob-cli's `just install-all` does the
same.

If automatic setup is unavailable, create the identity manually in Keychain Access:

1. Open Keychain Access and select the **login** keychain.
2. Choose Keychain Access › Certificate Assistant › Create a Certificate.
3. Name it exactly `Bob Mac Capture Local`.
4. Set Identity Type to **Self-Signed Root** and Certificate Type to **Code Signing**.
5. Give it a long validity period (ten years) and finish the assistant, storing the
   certificate in the login keychain.

On the first signed install, `codesign` prompts for keychain access: choose
**Always Allow** so future installs stay unattended. Prefer a GUI Terminal or a tmux
server started from one. Over SSH the login keychain is locked; `just signing-check`
runs the same identity check without building.

Verify an install with:

```bash
codesign -d -r- ~/Applications/"Bob Mac Capture.app"
```

A stable install shows `certificate leaf = H"…"`; an ad-hoc one shows a `cdhash`
designated requirement instead. Keychain unlock, password mismatch, and
`errSecInternalComponent` recovery are in
[Install › Signing](https://bobs-org.github.io/reference/mac-capture/install/#signing).

## License

[MIT](LICENSE)

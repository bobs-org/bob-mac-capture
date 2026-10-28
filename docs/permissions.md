---
title: "Mac Capture permissions"
description: "Accessibility, notification authorization, launch at login, and what Bob Mac Capture stores on disk, in memory, and in diagnostics."
---

macOS ties Accessibility, notification authorization, and launch-at-login trust to the installed code-signing identity, not only the bundle identifier. Keep one stable identity ("Bob Mac Capture Local") for the life of an install; see [Install](install.md#signing). Settings that request or display these grants are in [Settings](settings.md).

Recovery steps for a stale Accessibility switch, denied notifications, or a lingering Login Items row are in [Restore Mac Capture permissions](https://bobs-org.github.io/guides/restore-mac-capture-permissions/).

## Accessibility

Bob Mac Capture needs Accessibility to read Highlights tabs and observe ⌘S while Highlights is frontmost. Command-Y, Command-B, and Command-L in Highlights use that same tab read to open the Copy card on the focused PDF. Settings › References shows "Highlights tabs: Allowed / Not allowed" and never prompts. Tabs never asks at launch. Open Accessibility Settings from the Tabs card (an explicit gesture) clears a stale grant with `tccutil reset Accessibility org.bobs.bob-mac-capture` and then shows the system prompt; if the prompt does not grant trust it opens System Settings › Privacy & Security › Accessibility.

Accessibility is used only against Highlights: it reads window/tab attributes, selects or closes tabs, and passively checks key-down characters and modifier flags for ⌘S. It never consumes or re-posts the key; key-event text is not stored or logged. Names stay in memory. Bob Refs quits Highlights only after closing its last document. Tab names and closed-tab entries are never persisted.

macOS ties an ad-hoc app's grant to its exact `cdhash`, so every ad-hoc `just install` silently revokes the grant while System Settings still shows it on. Ad-hoc Settings caption: "Grants reset when an ad-hoc build is reinstalled." Signing every install with the stable identity keeps the grant across reinstalls. When an install changes the code signature, the installer clears the stale Accessibility row; grant the app again from Bob Refs › Tabs › Open Accessibility Settings.

## Notifications

Notification delivery and authorization persistence require the installed, signed `Bob Mac Capture.app` bundle (`just bundle` + `just install`), not `swift run` or a raw `.build` binary. Settings › Notifications shows live authorization (`Not requested`, `Denied — enable in System Settings`, `Authorized`, `Provisional`, `Ephemeral`, or `Unknown`), a button to request authorization while that is still possible, a link to the system notification settings pane, and a test-notification action. Settings › Diagnostics reports the current signing state.

An install never prompts for notification permission. Denied or not-yet-requested authorization is silent and non-fatal. Notification copy and the install-complete banner are in [Settings](settings.md#notification-copy). Scan notifications may show reference titles, as capture notifications already show task text.

## Launch at login

Launch at login is controlled from Settings via `SMAppService.mainApp`. Status values are `Enabled`, `Requires approval in System Settings`, `Not registered`, `App bundle not found`, or `Unknown`. If macOS reports "Requires approval in System Settings," open System Settings → General → Login Items and approve Bob Mac Capture there; the app cannot grant that approval for itself.

Uninstalling removes the launch-at-login registration's target, though macOS may keep a stale, non-functional Login Items entry until the next login — remove it manually from System Settings → General → Login Items if it lingers.

## Privacy

What is stored on disk, what stays in memory, and what diagnostic logs omit:

- Raw draft text lives only in the panel's in-memory draft and in the arguments passed
  directly to `bob`; it is never logged, written to `UserDefaults`, or emitted in a
  signpost or Diagnostics entry.
  `BobClientError.description` explicitly redacts the trailing draft argument from every
  command it echoes, and failure notifications carry only that bounded error message.
  Success notifications include Bob's semantic task/note text from the capture response,
  not the raw draft syntax; see [Settings › Notification copy](settings.md#notification-copy).
- Canceled drafts stashed with Control-C or by quitting with an unsent draft are
  stored in
  `~/Library/Application Support/org.bobs.bob-mac-capture/canceled-draft-stash.json`
  (directory mode 0700, file mode 0600). If the stash file is unreadable, it is renamed
  to `canceled-draft-stash.corrupt.json`, which can also hold captured text. They are
  never written to `UserDefaults`, notifications, signposts, logs, or Diagnostics.
  Settings' **Clear Stash...** action and capacity 0 delete both files.
- Diagnostics and Recent Activity in Settings are metadata only — status strings like
  "Ready," "Hotkey conflict," or "Target cache stale," never note content.
- Signposts carry event names and durations for Instruments, not payloads. See
  [Diagnostics](diagnostics.md).
- Wikilink note paths, aliases, heading text, and block previews are read locally by
  `bob` to build completion candidates and are held only in the in-memory completion
  response and the visible row content. They are never logged, written to
  `UserDefaults`, or included in a notification, signpost, or Diagnostics entry — the
  same guarantee the draft itself gets.
- `@route+` task completion metadata, task-section titles, and a user-authored block ID
  are sent only to the local `bob` subprocess. The app never opens or rewrites Markdown
  notes directly; Bob performs the vault write through `capture-task-id`, and the app
  updates the draft only after Bob confirms success.

### Bob Refs on disk and in memory

Refs files live outside the vault, every file mode 0600 in 0700
directories: the snapshot cache, open log, and NEW marks
(`refs-snapshot.json`, `refs-open-log.json`, `refs-new-marks.json`) under
`~/Library/Application Support/org.bobs.bob-mac-capture/`, and the
intrinsics cache (`intrinsics-v2.json`) with thumbnails
(`thumbs-v2/<sha256>.png`) under
`~/Library/Caches/org.bobs.bob-mac-capture/refs/`. The first v2 run
removes the legacy `intrinsics.json` and `thumbs/`, so stale
224 × 290 thumbnails are never upscaled. Annotation images that
`bob ref show` names are read from the vault, read-only, and the
decoded previews stay in a bounded in-memory cache; nothing new is
written to disk. The References
settings persist a small set of `UserDefaults` keys (the ⌃⇧⌘O and ⌘/
binding flags, the Highlights-frontmost open key, the Highlights Tabs
key (`refsHighlightsTabsKey`, default `cmdT`), the Highlights
override path, the scan-after-Highlights-save toggle, and the preview
notes page size). Accessibility is used
only against Highlights: it reads window and tab attributes, selects or
closes tabs, and checks key-down characters and modifiers only for ⌘S.
Key-event text is never stored or logged. Bob Refs quits
Highlights only after closing its last document. Tab names and closed-tab
entries stay in memory and are never persisted. Signposts
carry event names only, never note text.
Scan notifications may show reference titles, as capture notifications
already show task text; the Just scanned mark itself lives in memory
only and is never written to disk.

Uninstalling removes `~/Library/Application Support/org.bobs.bob-mac-capture`. The app stores only non-sensitive preferences (bob path, vault path, hotkey choice, canceled-draft stash capacity, Refs keys above) in `UserDefaults` under `org.bobs.bob-mac-capture`.

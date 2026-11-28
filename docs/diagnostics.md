---
title: "Mac Capture diagnostics"
description: "Menu-bar icon states, Settings diagnostics, signposts, timeouts, Copy Diagnostic, and refs-rank for Bob Mac Capture."
---

Diagnostics are metadata only: status strings, event names, and bounded error messages, never captured text or note bodies. Storage rules are in [Permissions](permissions.md). The Settings rows that display this material are in [Settings](settings.md#diagnostics). Glyph rendering tests are in [Build](https://bobs-org.github.io/develop/mac-capture/build/).

## Menu-bar icon

The only always-visible surface is a purpose-designed monochrome mark: a geometric lowercase "b" (a vertical stem plus a circular bowl, one stroke weight) with a solid bullet centered in the bowl. The bullet is the captured thought — every capture becomes a bullet in the vault. AppKit tints the template image for light and dark menu bars, Liquid Glass wallpapers, and the highlighted (menu-open) state, with no bundled assets. The amber wake beacon is a separate color accessory, so it does not change the base glyph's template tint.

- **Ready**: the bullet-b. Tooltip and accessibility label are `Bob Mac Capture`.
- **bob unresolved**: the bullet becomes a "!". The tooltip reads
  `Bob Mac Capture — bob is not resolved. Check Settings.`, and the menu gains a
  `bob Not Resolved — Open Settings…` row above the healthy items.
- **Wake beacon**: a small amber alarm badge with the unacknowledged delivered-task count in the top-right corner. A separate color accessory keeps the base glyph template-tinted while preserving the badge's amber. The tooltip reads `Bob Mac Capture — N snoozed tasks ready` (or `1 snoozed task ready`), and the accessibility label names the count; the unresolved suffix is kept when both states coexist. Clearing follows the shared acknowledgement lifecycle: panel open, Open, +15m success, 60 minutes after delivery, day rollover, disable, or a change of vault or Bob executable. No stale capture-landed pulse restores a cleared count.
- **Capture landed**: after every successful submit, the bullet briefly swells and
  settles (420 ms). The pulse is skipped when Reduce Motion is on. Pulse frames read the live presentation, so a beacon cleared mid-pulse stays cleared, and the pulse coexists with the unresolved marker and the beacon.

## Settings diagnostics and Recent Activity

Settings › Snoozed Tasks shows Wake notice status (claim, capability, last receipt, channel, hold reason, verification, queue counts, restored count, failure — metadata only, never task text). Settings › Diagnostics shows the current app status string (selectable; starts as `Starting`), the signing diagnostic (`Not checked` until inspected), and a Recent Activity disclosure of the last 20 timestamped entries (`HH:mm:ss  message`). Each app-status change appends one entry; the list is in-memory only and never contains captured text.

A hotkey registration failure reports `Hotkey conflict` with the Carbon status, `Refs hotkey conflict: …`, `Capture alias hotkey conflict: …`, or `Refs alias hotkey conflict: …`. Highlights takeover conflicts name the chord and action and show a toast once per launch. Recovery is in [Resolve a Mac Capture hotkey conflict](https://bobs-org.github.io/guides/resolve-mac-capture-hotkey-conflict/). Target/route completion problems report `Target cache stale` with the scan error; recovery is in [Fix Mac Capture when bob is not resolved](https://bobs-org.github.io/guides/fix-mac-capture-bob-resolution/).

## Timeouts

Every `bob` invocation is bounded by a 20-second timeout (`BobProcessClient.defaultTimeout`) that terminates and reaps a wedged process instead of leaving the panel waiting indefinitely; a fired timeout surfaces as an actionable `BobClientError.timedOut` that names the timed-out command and never the captured text. Quit cancels every outstanding invocation via `cancelActiveProcess()`. A Bob Refs scan uses its own `refs-scan` lane with a 300 s timeout and never cancels another lane's work. Required commands and guard retries are in [Protocol](protocol.md).

## Copy Diagnostic

Capture errors keep the complete draft on screen. **Copy Diagnostic** next to the error copies the exact `bob` error message to the pasteboard (`BobClientError.description` redacts the trailing draft argument).

In Bob Refs, Copy Diagnostic on the load-failed card copies the refresh failure's bounded message; an open-error banner copies its own diagnostic first. Problem scans raise a banner: a warning with Copy Diagnostic for per-PDF failures (the footer can say `+N more · Copy Diagnostic lists them all`), an error with Scan Again and Copy Diagnostic for hard failures.

## Signposts

The app emits `os_signpost` intervals/events (subsystem `org.bobs.bob-mac-capture`,
category `capture`) around hotkey receipt, panel ordering, editor focus, parse,
completion, preview, submit, the settled `capture-related` lane, block-ID focus claims, plain-text paste
(`paste-plain-text`), notification scheduling, install-restart notification
requests (`install-restart-notification-requested`), the idle agenda
(intervals `agenda-refresh`, `agenda-measure`, `agenda-plan`; events
`agenda-unchanged`, `agenda-published`, `agenda-hold-released`), Bob Refs
(intervals `refs-pull`, `refs-refresh`, `refs-scan`, `refs-panel-show`,
`refs-panel-prepare`, `refs-panel-order`, `refs-library-publish`; event
`refs-today-skipped`), and the Ctrl+Tab panel switch
(interval `panel-switch`; event `panel-switch-key`), visible in
Instruments' Points of Interest / os_signpost templates. Capture show and hide add
intervals `capture-prepare` and `capture-dismiss`; the template shelf refresh
adds interval `templates-refresh`; the related lane adds interval
`capture-related` and metadata-only events `capture-related-unsupported`,
`capture-related-failed`, `capture-related-publish` (settled response changed
the visible rows), and `capture-related-empty` (settled response had no
matches); the snooze wake lifecycle adds metadata-only events
`snooze-receipt-read`, `snooze-hold`, `snooze-return`, `snooze-verify`,
`snooze-present`, `snooze-record`, `snooze-action`, and `snooze-withdraw` around receipt
read, hold/return, verification, presentation, the Notification Center record post,
action, and withdrawal. Every snooze event carries public metadata: wake ID, hold or
drop reason, task count, and channel, never task titles. Record posts use
`snooze-record` so one presentation is one `snooze-present`. These, and the bounded
Recent Activity list in Settings, are metadata-only by construction — see
[Permissions](permissions.md#privacy).

Inspect them with:

```bash
log show --signpost --predicate 'subsystem == "org.bobs.bob-mac-capture"'
```

Settings › Snoozed Tasks includes a `Records:` line for the Notification Center
authorization status (`Not requested`, `Denied — enable in System Settings`,
`Authorized`, …). Snooze posts never call `requestAuthorization`; Enable in Settings
is the only prompt.

## Acceptance probe

The in-app probe is compiled into every Mac Capture build and stays off for the
production identity `org.bobs.bob-mac-capture`. It enables only when the running
bundle ID starts with `org.bobs.bob-mac-capture.accept` and that domain has
`snoozeAcceptanceProbe = true`. The accept-noauth scratch identity matches the same
prefix. The probe never parses or writes the vault.

The isolated harness `Scripts/snooze-accept.sh` is the only supported client:

- `up` seeds `snoozeAcceptanceProbe` on the accept domain.
- `probe <command> [args…]` atomically writes
  `$XDG_STATE_HOME/bob-mac-capture-accept/probe/request.json`, posts Darwin
  `org.bobs.bob-mac-capture.accept.probe`, and prints `response-<seq>.json`.
- Commands: `snapshot [png]`, `press <open|snooze15|dismiss|body|row:N>`,
  `hover <enter|exit>`,
  `set <snoozeWakeAnnounce|snoozeWakeChime|snoozeWakeHoldWhileAway|snoozeWakeHoldDuringMeetings|bobDirectory|bobExecutableOverride> <value>`,
  `override <reduce-motion|reduce-transparency> <on|off|system>`,
  `open-sink <on|off>` (on by default in probe mode), `panel <show|hide>`.
- `rebuild --sha`, `idle`, `evidence --since`, `shim passthrough|oldbob|off`,
  `variant noauth|accept`, and `lockwatch` drive the unattended accept checks.

Open in probe mode records the Obsidian URL instead of launching it. Press finds the
live HUD control by `accessibilityIdentifier` and calls `accessibilityPerformPress()`,
falling back to the controller handler only if that fails, and reports which path ran.

## refs-rank

`swift run refs-rank` ranks a `bob ref list` snapshot with the same ranker the panel uses. Ranking rules, NEW, and the Newest timeline are in [Bob Refs](refs.md#tuning). The binary is never bundled: `Scripts/bundle.sh` copies only the `BobMacCapture` product.

```bash
swift run refs-rank [--plan plan.json] [--opens open-log.json]
[--new-marks refs-new-marks.json] [--scope chats]
[--now 2026-10-08T09:00:00] [--tz America/New_York]
[--newest] [query...] < ref-list.json
```

`--now` accepts a full ISO 8601 time with an offset or a local date-time without one, interpreted in `--tz` (default: the current time zone). Browse mode prints the sections; search mode prints `rank  tier  score (m P W L F R)  state  kind  title` with padded columns (rank 4, tier 9, state 8, kind 7), each followed by its why-here line. `--newest` prints the Newest timeline. `--new-marks` loads Mac-local NEW marks.

```bash
bob ref list -R all -A -f json -g | swift run refs-rank --newest
```

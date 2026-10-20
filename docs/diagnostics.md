---
title: "Mac Capture diagnostics"
description: "Menu-bar icon states, Settings diagnostics, signposts, timeouts, Copy Diagnostic, and refs-rank for Bob Mac Capture."
---

Diagnostics are metadata only: status strings, event names, and bounded error messages, never captured text or note bodies. Storage rules are in [Permissions](permissions.md). The Settings rows that display this material are in [Settings](settings.md#diagnostics). Glyph rendering tests are in [Build](https://bobs-org.github.io/develop/mac-capture/build/).

## Menu-bar icon

The only always-visible surface is a purpose-designed monochrome mark: a geometric lowercase "b" (a vertical stem plus a circular bowl, one stroke weight) with a solid bullet centered in the bowl. The bullet is the captured thought — every capture becomes a bullet in the vault. AppKit tints the template image for light and dark menu bars, Liquid Glass wallpapers, and the highlighted (menu-open) state, with no bundled assets.

- **Ready**: the bullet-b. Tooltip and accessibility label are `Bob Mac Capture`.
- **bob unresolved**: the bullet becomes a "!". The tooltip reads
  `Bob Mac Capture — bob is not resolved. Check Settings.`, and the menu gains a
  `bob Not Resolved — Open Settings…` row above the healthy items.
- **Capture landed**: after every successful submit, the bullet briefly swells and
  settles (420 ms). The pulse is skipped when Reduce Motion is on.

## Settings diagnostics and Recent Activity

Settings › Diagnostics shows the current status string (selectable; starts as `Starting`), the signing diagnostic (`Not checked` until inspected), and a Recent Activity disclosure of the last 20 timestamped entries (`HH:mm:ss  message`). Each status change appends one entry; the list is in-memory only and never contains captured text.

A hotkey registration failure reports `Hotkey conflict` with the Carbon status, or `Refs hotkey conflict: …`. Recovery is in [Resolve a Mac Capture hotkey conflict](https://bobs-org.github.io/guides/resolve-mac-capture-hotkey-conflict/). Target/route completion problems report `Target cache stale` with the scan error; recovery is in [Fix Mac Capture when bob is not resolved](https://bobs-org.github.io/guides/fix-mac-capture-bob-resolution/).

## Timeouts

Every `bob` invocation is bounded by a 20-second timeout (`BobProcessClient.defaultTimeout`) that terminates and reaps a wedged process instead of leaving the panel waiting indefinitely; a fired timeout surfaces as an actionable `BobClientError.timedOut` that names the timed-out command and never the captured text. Quit cancels every outstanding invocation via `cancelActiveProcess()`. A Bob Refs scan uses its own `refs-scan` lane with a 300 s timeout and never cancels another lane's work. Required commands and guard retries are in [Protocol](protocol.md).

## Copy Diagnostic

Capture errors keep the complete draft on screen. **Copy Diagnostic** next to the error copies the exact `bob` error message to the pasteboard (`BobClientError.description` redacts the trailing draft argument).

In Bob Refs, Copy Diagnostic on the load-failed card copies the refresh failure's bounded message; an open-error banner copies its own diagnostic first. Problem scans raise a banner: a warning with Copy Diagnostic for per-PDF failures (the footer can say `+N more · Copy Diagnostic lists them all`), an error with Scan Again and Copy Diagnostic for hard failures.

## Signposts

The app emits `os_signpost` intervals/events (subsystem `org.bobs.bob-mac-capture`,
category `capture`) around hotkey receipt, panel ordering, editor focus, parse,
completion, preview, submit, block-ID focus claims, plain-text paste
(`paste-plain-text`), notification scheduling, install-restart notification
requests (`install-restart-notification-requested`), the idle agenda
(intervals `agenda-refresh`, `agenda-measure`, `agenda-plan`; events
`agenda-unchanged`, `agenda-published`, `agenda-hold-released`), and Bob Refs
(intervals `refs-pull`, `refs-refresh`, `refs-scan`, `refs-panel-show`,
`refs-panel-prepare`, `refs-panel-order`), visible in
Instruments' Points of Interest / os_signpost templates. These, and the bounded
Recent Activity list in Settings, are metadata-only by construction — see
[Permissions](permissions.md#privacy).

Inspect them with:

```bash
log show --signpost --predicate 'subsystem == "org.bobs.bob-mac-capture"'
```

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

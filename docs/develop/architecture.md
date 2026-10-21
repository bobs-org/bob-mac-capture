---
title: "Mac Capture architecture"
description: "Source layout, process and cache boundaries, and failure rules behind the Mac capture panel."
---

How the panel is built. Externally observable behavior stays in the [reference](https://bobs-org.github.io/reference/mac-capture/); this page names the boundaries that keep it there.

## Layout

`CaptureCore` imports only Foundation and runs `bob` directly through `Process` with argv arrays and an explicit GUI-safe environment. The app target owns the `NSPanel`, the SwiftUI panel, the editor palette (`CaptureEditorPalette`), the grammar gate (`BlockIDRules`: `bob` is the only authority for the grammar), the agenda store, and the card views. Render fixtures for close, adjust, link-move, created-start, Pomodoro-block, and task-block designs render to PNG when `BOB_MAC_CAPTURE_RENDER_DIR` is set.

## Lanes

Subprocess work stays off the hotkey path, which uses a pre-warmed non-activating `NSPanel`. One shared lane serves the agenda (`capture-pomodoros --tasks`); typing `@@` after an absorbable marker and typing `^` / `:` after a complete ID reuse the rewrite lane. Similar-task lookup has its own cancellable lane: it calls `capture-related --format json -- DRAFT` once after 350 ms without edits. The band state keeps existing rows while a new response is pending. One refresh flies at a time with at most one follow-up; a rewrite applies only when the visible draft still matches the submitted draft, and every show, submit, wake, unlock, day change, and clock change revalidates.

## Caches

The agenda snapshot publishes nothing when byte-identical and is never shown when its date is not today. A related-command rejection is cached per Bob executable identity, so an older Bob hides the band without retrying on later drafts. Route completion strips the `@@` sigil like the server; the link picker filters `bob`'s snapshot locally. Capture targets cache at launch and on panel open and invalidate on filtered vault events (never `.git/`, attachments, or dot-path-only batches). Templates check out in app memory; the last-used filing parent persists after a successful submit.

## Failure boundaries

A malformed `capture-parse` span set is ignored instead of partially applied after UTF-8 range validation. Unknown span kinds, contexts, and groups degrade to neutral text, generic rows, and `note` groups. Additive fields decode with `decodeIfPresent`; a mismatched `schema_version` still rejects. Every `bob` call is bounded by `BobProcessClient.defaultTimeout` with reap and `cancelActiveProcess()` on quit. Guard flags (`--refuse-override`, `--require-pull-in-choice`) retry once without the flag on unexpected-argument rejection and remember the answer per executable.

Reference: [panel](https://bobs-org.github.io/reference/mac-capture/capture-panel/), [pickers](https://bobs-org.github.io/reference/mac-capture/pickers/), [previews](https://bobs-org.github.io/reference/mac-capture/capture-previews/), [protocol](https://bobs-org.github.io/reference/mac-capture/protocol/). Contributor recipes: [Build](build.md), [CI](ci.md).

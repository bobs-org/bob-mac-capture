---
title: "Mac Capture CI"
description: "GitHub Actions gates for Bob Mac Capture: format, build, test, bundle, launch signpost, and installer restart."
---

CI facts for the Mac app. Local recipes are in [Build](build.md). Launch and install-restart signposts are in [Diagnostics](https://bobs-org.github.io/reference/mac-capture/diagnostics/#signposts).

## Workflow

GitHub Actions runs on `macos-26` for pushes to `master` and pull requests. Formatting runs first, and a Swift parse error there skips Build, Test, Bundle, and the install gates, so a red lint step can hide compile errors further down. The workflow
checks Swift formatting, `swift build`, `swift test`, bundle assembly, `plutil -lint`,
signature verification, and the bundle identifier. It also launches the bundled app and
requires the `launch-complete` signpost to appear in the unified log before quitting it,
so a broken entry point (no delegate assigned, no menu bar item, no hotkey) fails CI
instead of shipping silently. The installer gate then installs into a temporary `HOME`
while stopped (must not auto-launch), relaunches that exact bundle through a running
reinstall (old PID gone, one new PID, a fresh `launch-complete` and
`install-restart-notification-requested`), and reinstalls once more while stopped
(must stay stopped). An ordinary launch of the installed copy must not emit the
install-restart notification signpost.

## Render fixtures

The Test step sets `BOB_MAC_CAPTURE_RENDER_DIR` and uploads that directory as the `render-fixtures` artifact (14-day retention) even when the job fails. Tests that opt in write PNGs there (menu-bar glyph, close/adjust/link-move/created-start cards, Pomodoro-block and task-block designs, Refs panel). Architecture names those families; [Build](build.md#menu-bar-glyph-fixtures) has the glyph filter. Selecting those PNGs into the mounted docs site is out of this page's scope.

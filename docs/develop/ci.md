---
title: "Mac Capture CI"
description: "GitHub Actions gates for Bob Mac Capture: format, build, test, bundle, launch signpost, and installer restart."
---

CI facts for the Mac app. Local recipes are in [Build](build.md). Launch and install-restart signposts are in [Diagnostics](https://bobs-org.github.io/reference/mac-capture/diagnostics/#signposts).

## Workflow

GitHub Actions runs on `macos-26` for pushes to `master`, pushes to `ci/**`, and pull
requests. The `ci/**` trigger exists so `Scripts/macos-ci-check` can run the workflow
from a throwaway branch without opening a pull request. Formatting runs first, and a
Swift parse error there skips Build, Test, Bundle, and the install gates, so a red lint
step can hide compile errors further down. Before the Swift toolchain steps, CI runs the
offline Python script tests (`Scripts/test_docs_scripts.py` and
`Scripts/test_macos_ci_check.py`) with the runner's Python; those tests never invoke the
live gate. The workflow
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

## Precommit macOS check

`Scripts/macos-ci-check` snapshots this checkout's current working tree into a throwaway
commit object through a temporary index, pushes it only to
`refs/heads/ci/precommit/<id>`, waits for the GitHub Actions run for that exact SHA,
prints every macOS step's verdict, and deletes the remote branch. HEAD, local branches,
the caller's index, and working files stay unchanged. The snapshot includes tracked
modifications, deletions, and non-ignored untracked files as they exist on disk,
including partially staged files' worktree contents. Ignored files and dirty submodules
are not uploaded; dirty submodules are refused.

Prerequisites: `python3`, `git`, authenticated `gh`, push access, and a GitHub origin
that identifies `bobs-org/bob-mac-capture`. The command never prints credentials or logs
in for you.

Default deadlines, overridable with positive finite `BOB_MACOS_CI_*_SECONDS` values:

| Variable | Default | Meaning |
| --- | --- | --- |
| `BOB_MACOS_CI_DISCOVERY_SECONDS` | 300 | Find the first matching run after push |
| `BOB_MACOS_CI_TOTAL_SECONDS` | 5400 | Overall check, including push and wait |
| `BOB_MACOS_CI_COMMAND_SECONDS` | 60 | Each git/gh call, capped by remaining time; leftover below 1s (or the command cap) is the deadline |
| `BOB_MACOS_CI_CLEANUP_SECONDS` | 120 | Cancel an unfinished run and delete the ref |
| `BOB_MACOS_CI_POLL_SECONDS` | 10 | Interval between status polls |

The selected `ci.yml` push run must pass. Required macOS coverage is job
`macOS 26 SwiftPM` with steps `Lint Swift formatting`, `Build`, `Test`, `Bundle`,
`Verify plist and signature`, `Launch smoke test`, and `Install and reinstall`.
Conditional diagnostic and upload steps may be skipped.

Exit codes: `0` the workflow and required macOS checks passed and remote branch
deletion was verified; `1` the selected run completed with a real CI failure; `2`
verification could not finish (missing prerequisites, no matching run, deadline,
cancellation, missing coverage, or cleanup failure). Cleanup failure takes precedence
and returns `2` while still reporting any observed CI failure.

SIGINT and SIGTERM stop child processes, cancel an unfinished selected run when
possible, delete only this invocation's ref, and verify it is gone. An already-absent
ref is success. A ref that now points at a different SHA is not deleted. If deletion
cannot be verified, the printed repository, ref, snapshot SHA, and deletion command are
the recovery path.

Offline tests, which never invoke the live gate:

```sh
just check-scripts
```

From a SASE agent, run the live gate through `sase monitor start` with profile `verify`
and a timeout longer than 90 minutes plus the two-minute cleanup budget (for example
`--timeout 95m`). The command snapshots and pushes before waiting, so `verify` is the
right profile. `--next` should inspect the result, repair if needed, record verification
evidence, and close the assigned bead. Wait for `sase monitor start` itself to exit.

## Render fixtures

The Test step sets `BOB_MAC_CAPTURE_RENDER_DIR` and uploads that directory as the `render-fixtures` artifact (14-day retention) even when the job fails. Tests that opt in write PNGs there (menu-bar glyph, close/adjust/link-move/created-start cards, Pomodoro-block and task-block designs, Refs panel). Architecture names those families; [Build](build.md#menu-bar-glyph-fixtures) has the glyph filter. [Render fixtures](render-fixtures.md) explains the curated documentation images, provenance, refresh commands, and appearance checks.

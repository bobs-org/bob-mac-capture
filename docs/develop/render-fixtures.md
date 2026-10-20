---
title: Mac Capture render fixtures
description: Refresh the synthetic CI panel images, inspect their provenance, and preview them in both Bob documentation builders.
---

# Render fixtures

The documentation images are real SwiftUI renders from synthetic test inputs. They
show the agenda, a task-completion card, and the Refs browse panel. They do not read
an installed app's state or a personal vault. The [CI workflow](ci.md) uploads
`render-fixtures` with 14-day retention; an upload can exist even when CI fails.
The documentation importer accepts only a completed, successful `ci.yml` run on
`master`.

## Sources and curation

The explicit selection lives in `Scripts/docs_media.py`. Each filename below has
`-light.png` and `-dark.png` variants. Capture fixtures use the standard 760-point
panel width; Refs uses 880 points. The renderers produce PNGs at scale 2.

| Artifact stem | Synthetic input | Documentation stem |
| --- | --- | --- |
| `agenda-agenda-current-760` | `CaptureAgendaDesignTests`, `Tests/Fixtures/agenda-current.json` | `capture-agenda` |
| `task-complete-task-complete-strike-760` | `TaskCompleteDesignTests`, `Tests/Fixtures/task-complete-strike.json` | `task-completion` |
| `refs-browse-880` | `RefsPanelDesignTests.makeFixture(now:)`, `renderBrowse` | `refs-browse` |

The light image uses the documentation stem directly; the dark image adds `-dark`.
`RenderFixtureWriter` serves the agenda and Refs tests; the completion test uses
`ImageRenderer` directly. The Refs fixture fixes its clock and constructs its library
in a temporary directory with stub openers. Agenda and completion data come from
committed JSON fixtures.

Menu-bar artwork has its own `StatusItemGlyphDesignTests`: idle, active, and blocked
states, light/dark backdrops, and a pulse filmstrip. Those tiny glyphs help inspect
the icon, while the documentation selection illustrates panel content. See
[Build](build.md#menu-bar-glyph-fixtures) to render the glyph family.

## Refresh the images

Install Python 3, GitHub CLI (`gh`), and `just`, and authenticate `gh` for Actions
artifact access. From the Mac repository:

```bash
just docs-test
just docs-media
```

`docs-media` queries the latest successful master run, checks that its named artifact
exists and is unexpired, then downloads it with `gh run download --name render-fixtures`
into a temporary directory. It validates every selected PNG before replacing the
managed `docs/images/` directory and `docs/media.yml`. A missing run, authentication
error, failed download, expired artifact, or absent/corrupt selected image leaves the
previous outputs intact. It does not fall back to an older run.

The manifest records the run URL and ID, full commit SHA, original artifact filename,
fixture identity, and ISO run timestamp in `source`; `date` is that run's UTC calendar
date. The manifest is JSON, which is valid YAML, and keeps the site's two-key
`source`/`date` schema. Commit images and manifest together. The importer owns both
paths; extend its manifest generation before adding other documentation images.

For a separate inspection download, obtain the ID from the first command and use it
in the second:

```bash
gh run list --repo bobs-org/bob-mac-capture --workflow ci.yml --branch master --status success --limit 1
gh run download RUN_ID --repo bobs-org/bob-mac-capture --name render-fixtures --dir /tmp/bob-render-review
```

Before changing the selection, read the fixture and renderer at the recorded SHA.
Inspect the pixels for personal information, readable labels, and useful framing.
Keep a small standard-width selection rather than committing the whole artifact.

## Preview the mounted pages

From this repository, point at the bob-cli checkout containing the site:

```bash
BOB_CLI_DIR=/path/to/bob-cli just docs-check
```

The wrapper resolves `BOB_CLI_DIR`, then the sibling `../bob-cli`, then a managed
clone under `${XDG_CACHE_HOME:-$HOME/.cache}/bob-mac-capture-docs/bob-cli`.
An explicit empty or invalid override fails. User checkouts are never fetched or
reset; only the managed cache with the expected origin is refreshed. It forwards this
Mac checkout as `BOB_DOCS_BOB_MAC_CAPTURE_DIR` and preserves the docs gate's exit code.
Quote paths containing spaces. SASE agents must use an explicit `BOB_CLI_DIR` for
their authorized checkout, opened through `/sase_repo` when necessary.

The wrapper checks the assembled site, including the homepage's mounted agenda image.
It does not import new images or install the app. `just docs-test` exercises importer
and wrapper failures offline with local PNG fixtures and stub `gh`, `git`, and `just`.

## Check appearance in both builders

From bob-cli, set `BOB_DOCS_BOB_MAC_CAPTURE_DIR` to this checkout and run:

```bash
just docs-build
just docs-build-material
```

Inspect each output before running the next builder, which replaces `target/docs/site/`.
Serve that directory locally or use [the shared preview tooling](https://bobs-org.github.io/develop/build/).
Check the homepage, idle agenda, capture previews, and Refs reference at desktop
and 360-pixel widths in both themes. Images retain their aspect ratios; their links
open the original PNG for small text.

Light/dark pairs use `#only-light` and `#only-dark`. Check computed visibility in
each strict builder: exactly one image must be visible in each theme, with no empty
duplicate image taking space. If either builder stops honoring the pair, keep only
the light variant in `APPEARANCES`, remove the dark image links and light fragments,
and re-import. Do not add theme-specific CSS to conceal a builder incompatibility.

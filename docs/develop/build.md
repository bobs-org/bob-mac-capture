---
title: "Mac Capture build"
description: "Toolchain selection, portable checks, bundle and test recipes, and glyph render fixtures for Bob Mac Capture."
---

Contributor recipes for building Bob Mac Capture. Install, signing identity, updates, and uninstall stay in [Install](https://bobs-org.github.io/reference/mac-capture/install/). Architecture boundaries are in [Architecture](architecture.md). CI gates are in [CI](ci.md).

## Recipes

```bash
just format-lint
just build
just test
just bundle
```

On a host without Xcode, only CaptureCore, RefsCore, and refs-rank build; `just portable-check` lints every Swift file and builds and tests those targets, but cannot type-check the `BobMacCapture*` targets.

`just typecheck-tests` type-checks all test targets on a Mac with only Command Line Tools.

`just bundle` creates `.build/bundle/Bob Mac Capture.app` and signs it with the ad-hoc identity `-`, which is the right default for agent scratch builds. `just install` instead resolves its identity: an explicit `--identity` or `CODESIGN_IDENTITY` wins (including `-`), otherwise it signs with the stable "Bob Mac Capture Local" identity when the login keychain holds it, and falls back to ad-hoc with a loud warning:

```bash
just install ~/Applications
just install ~/Applications "Apple Development: Name (TEAMID)"
```

`just install` is the complete update for the selected target: it restarts that installed copy if it was already running, and leaves it stopped otherwise. See [Install](https://bobs-org.github.io/reference/mac-capture/install/#updating-reinstalling-and-rollback).

Ad-hoc signatures are useful for local development, but notification permissions, Accessibility grants, and launch-at-login trust are tied to the installed signed bundle. Reinstalling with a new or expired certificate can require reauthorizing those system permissions.

`just signing-check` runs the identity check without building. `just signing-identity` creates the stable local signing identity from a GUI Terminal.

## Toolchain selection

macOS 26 with Command Line Tools for Xcode 26+ or Xcode 26+. SwiftPM from the selected Apple toolchain. `justfile`, `Scripts/bundle.sh`, and CI all route Swift invocations through `Scripts/xcode-swift.sh`, which resolves `swift` via `xcrun` from `DEVELOPER_DIR` or `xcode-select --print-path` rather than trusting a bare `swift` on `PATH`. This accepts either `/Library/Developer/CommandLineTools` or a full Xcode developer directory when the selected tools provide a macOS 26+ SDK and Apple Swift executable. It also keeps a Swift.org / Swiftly installation, or any other shadowing `swift`, from compiling ordinary targets while `swift test` later fails at `import XCTest`. Compare what's actually selected:

```bash
command -v swift; swift --version           # whatever is first on PATH
./Scripts/xcode-swift.sh --version           # what build/test/bundle actually use
```

If the two differ, `./Scripts/xcode-swift.sh --version` fails, or `import XCTest` fails to compile, update or select matching Apple developer tools rather than migrating tests off XCTest:

```bash
sudo xcode-select --switch /Library/Developer/CommandLineTools
# or:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
# or, scoped to one shell:
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
# or:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

A `swift test` failure with `no such module 'XCTest'` is this toolchain mismatch.

## Menu-bar glyph fixtures

The menu-bar mark is drawn in code (`Sources/BobMacCapture/StatusItemGlyph.swift`) as a template image. User-visible states are in [Diagnostics](https://bobs-org.github.io/reference/mac-capture/diagnostics/#menu-bar-icon). To eyeball the real AppKit rendering:

```bash
BOB_MAC_CAPTURE_RENDER_DIR=… ./Scripts/xcode-swift.sh test --filter StatusItemGlyphDesignTests
```

Inspect the PNGs it writes: each state at 1x, 2x, and 3x on light, dark, and accent backgrounds, 8x enlargements, and a pulse filmstrip. CI uploads the directory as the `render-fixtures` artifact; see [CI](ci.md).

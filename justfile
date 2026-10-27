set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default: test

format-lint:
    if command -v swift-format >/dev/null 2>&1; then \
      swift-format lint --recursive Package.swift Sources Tests; \
    else \
      ./Scripts/xcode-swift.sh format lint --recursive Package.swift Sources Tests; \
    fi

build:
    ./Scripts/xcode-swift.sh build

test:
    ./Scripts/xcode-swift.sh test

# Gate for hosts without Xcode (Linux): parse-lint every Swift file, then build and
# test the portable CaptureCore/RefsCore targets with the PATH Swift toolchain.
portable-check:
    if command -v swift-format >/dev/null 2>&1; then \
      swift-format lint --recursive Package.swift Sources Tests; \
    else \
      swift format lint --recursive Package.swift Sources Tests; \
    fi
    swift build --build-tests
    swift test

typecheck-tests:
    ./Scripts/typecheck-tests.sh

bundle identity="-":
    ./Scripts/bundle.sh --identity "{{identity}}"

# An empty identity means "resolve": install.sh signs with the stable
# "Bob Mac Capture Local" identity, creating it when missing, and falls back
# to ad-hoc with a warning if creation needs a GUI Terminal. Before building,
# install checks the identity and offers to unlock a locked login keychain in a
# terminal. A mismatched login keychain password also blocks signing and offers
# a one-run unlock with the previous password. bundle keeps its ad-hoc default.
install target="~/Applications" identity="":
    ./Scripts/install.sh --target "{{target}}" --identity "{{identity}}"

# Checks, without building or installing, that codesign can use the install
# signing identity from this session. In a terminal, it offers to unlock a
# locked login keychain or a mismatched login keychain with the previous
# password for this run.
signing-check identity="":
    ./Scripts/install.sh --check-signing --identity "{{identity}}"

# Creates the stable local signing identity from a GUI Terminal on the Mac.
signing-identity:
    ./Scripts/create-signing-identity.sh

all: format-lint build test bundle

# Import reviewed synthetic panel images from the latest successful master CI.
docs-media:
    ./Scripts/docs-media.sh

# Preview this checkout's mounted pages through bob-cli's full documentation gate.
docs-check:
    ./Scripts/docs-check.sh

# Offline importer and preview-wrapper behavior tests.
docs-test:
    bash -n Scripts/docs-media.sh Scripts/docs-check.sh
    python3 -B Scripts/test_docs_scripts.py

# Offline script tests, including the macOS CI precommit gate.
check-scripts: docs-test
    python3 -B Scripts/test_macos_ci_check.py

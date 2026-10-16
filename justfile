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
# to ad-hoc with a warning if creation needs a GUI Terminal. bundle keeps its
# ad-hoc default.
install target="~/Applications" identity="":
    ./Scripts/install.sh --target "{{target}}" --identity "{{identity}}"

# Creates the stable local signing identity from a GUI Terminal on the Mac.
signing-identity:
    ./Scripts/create-signing-identity.sh

all: format-lint build test bundle

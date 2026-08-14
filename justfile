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

bundle identity="-":
    ./Scripts/bundle.sh --identity "{{identity}}"

install target="~/Applications" identity="-":
    ./Scripts/install.sh --target "{{target}}" --identity "{{identity}}"

all: format-lint build test bundle

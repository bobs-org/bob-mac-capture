set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default: test

format-lint:
    if command -v swift-format >/dev/null 2>&1; then \
      swift-format lint --recursive Package.swift Sources Tests; \
    else \
      swift format lint --recursive Package.swift Sources Tests; \
    fi

build:
    swift build

test:
    swift test

bundle identity="-":
    ./Scripts/bundle.sh --identity "{{identity}}"

install target="~/Applications" identity="-":
    ./Scripts/install.sh --target "{{target}}" --identity "{{identity}}"

all: format-lint build test bundle

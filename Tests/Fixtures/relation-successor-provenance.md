# Relation successor fixture provenance

- Bob source SHA: 71907dab7ceb7dab45a401a700e7069cd767bc24
- Bob binary version: bob 0.4.0
- Generator: Scripts/generate-relation-successor-fixtures.sh
- Build command: CARGO_TARGET_DIR=<isolated-target> cargo build --release --bin bob
- Generator command: BOB_SOURCE=<opened bob-cli master checkout> BOB_BIN=<isolated-target>/release/bob Scripts/generate-relation-successor-fixtures.sh
- Clock: BOB_NOW=2026-11-02 09:30:00, TZ=UTC0
- Vault, config, XDG state, and cache are temporary and isolated for each scenario.
- Fixture transformation: replace only the generated scratch root with /tmp/bob-mac-capture-relation-successor-fixture.

The generator asserts each response's expected relation payload. The mixed x*!2
vault explicitly contains both a dependency hand-off and a relation successor offer.
The required-choice refusal, -p none, and opaque-key selection run against separate
scratch vaults.

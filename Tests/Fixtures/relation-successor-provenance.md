# Relation successor fixture provenance

- Bob source SHA: 0346d828011a5f5a0c4ef4d526fa80583dab7ee6
- Bob binary version: bob 0.4.0
- Generator: Scripts/generate-relation-successor-fixtures.sh
- Build command: cargo build --bin bob (debug, workspace target)
- Generator command: BOB_SOURCE=<opened bob-cli master checkout> BOB_BIN=<checkout>/target/debug/bob Scripts/generate-relation-successor-fixtures.sh
- Clock: BOB_NOW=2026-11-02 09:30:00, TZ=UTC0
- Vault, config, XDG state, and cache are temporary and isolated for each scenario.
- Fixture transformation: replace only the generated scratch root with /tmp/bob-mac-capture-relation-successor-fixture.

The generator asserts each response's expected relation payload. The mixed x*!2
vault explicitly contains both a dependency hand-off and a relation successor offer.
The required-choice refusal, -p none, and opaque-key selection run against separate
scratch vaults. Committed toggle and nested selections, blocked scheduled/project
held cases, and the primary hand-off with a secondary relation reason each run on
their own scratch vaults with genuine Bob output.

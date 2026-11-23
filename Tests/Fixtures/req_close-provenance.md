# Requirement close fixture provenance

Generated with `Scripts/generate-req-close-fixtures.sh` from:

- Bob binary: supplied through `BOB_BIN`
- Version: bob 0.6.0
- bob-cli source revision: `b1fa8ad6de8c3818152296f7c9af7cb2ec21ed1e`
- Command: `BOB_SOURCE_REV=b1fa8ad6de8c3818152296f7c9af7cb2ec21ed1e BOB_BIN=<current bob-cli target/debug/bob> Scripts/generate-req-close-fixtures.sh`

The requirement group uses the semantic `requirement` glyph token and full `requirements` scope wording. Task-block requirement lines carry Bob's `req: {depth, state}` annotation; a close preview reports `met` even though stored checkboxes stay `[ ]`.

The preview and mixed fixtures are Bob dry runs from disposable synthetic vaults. The Met fixture is a real default-Met close: its receipt reports Met, the owner closes, and all requirement checkboxes remain `[ ]`. The write fixture is a real drop verdict with Bob's receipt. The stale fixture changes the row after its preview and records Bob's write-free `req_close_stale` response with `current.groups`. The legacy fixture uses the current Bob's explicit offer-only handshake, then removes the additive requirement capability, receipts, and line annotations to model a pre-requirements payload.

`req_close/vectors.json` is copied byte for byte from bob-cli's `tests/fixtures/req_close/vectors.json`; bob-cli owns it. Change the source vectors and contract there first, then copy the file and update this README/provenance.

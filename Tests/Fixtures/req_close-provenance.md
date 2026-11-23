# Requirement close fixture provenance

Generated with `Scripts/generate-req-close-fixtures.sh` from:

- Bob binary: supplied through `BOB_BIN`
- Version: bob 0.6.0
- bob-cli source revision: `9d0cbfbe165d`
- Command: `BOB_SOURCE_REV=9d0cbfbe165d BOB_BIN=<current bob-cli target/debug/bob> Scripts/generate-req-close-fixtures.sh`

The preview and mixed fixtures are Bob dry runs from disposable synthetic vaults. The Met fixture is a real default-Met close: its receipt reports Met, the owner closes, and all requirement checkboxes remain `[ ]`. The write fixture is a real drop verdict with Bob's receipt. The stale fixture changes the row after its preview and records Bob's write-free `req_close_stale` response with `current.groups`. The legacy fixture uses the current Bob's explicit offer-only handshake, then removes only the additive requirement capability and receipts to model a pre-requirements payload.

`req_close/vectors.json` is copied byte for byte from bob-cli's `tests/fixtures/req_close/vectors.json`; bob-cli owns it. Change the source vectors and contract there first, then copy the file and update this README/provenance.

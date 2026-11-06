# Offer-close fixture provenance

Generated with Scripts/generate-offer-close-fixtures.sh from:

- Bob binary: supplied through the BOB_BIN environment variable
- Version: bob 0.4.0

capture-offer-close-preview.json is a dry-run with two existing dependent offers and Bob-authored close descriptors. capture-offer-close-write.json is a real Done verdict with the recover-only receipt. The stale-key, new-task refusal, and conflicting-pick payloads are real Bob failures. capture-offer-close-legacy.json is derived from the real preview by removing the additive close fields to model an older Bob response.

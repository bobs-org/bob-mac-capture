# Requirement marker fixture provenance

Generated on 2026-11-23 with installed `bob 0.6.0` (capture grammar 29).
These read-only replies exercise the Mac editor's existing expansion and atomic
Backspace behavior with a multibyte character before the requirement marker.

```bash
bob capture-rewrite --cursor 14 --format json -- $'Ship 🧭\n- [ '
bob capture-parse --format json -- $'Ship 🧭\n- [ ] '
```

The outputs are stored verbatim in `capture-rewrite-requirement-marker.json` and
`capture-parse-requirement-marker.json`, respectively. No vault write is involved.

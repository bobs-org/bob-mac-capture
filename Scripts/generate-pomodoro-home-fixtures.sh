#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bob_bin="${BOB_BIN:-$(command -v bob || true)}"
if [[ -z "$bob_bin" || ! -x "$bob_bin" ]]; then
  echo "Set BOB_BIN to an installed bob executable." >&2
  exit 1
fi

scratch_root="/tmp/bob-pomodoro-homes-fixture-vault"
if [[ -e "$scratch_root" ]]; then
  echo "Refusing to overwrite existing scratch path: $scratch_root" >&2
  exit 1
fi
mkdir -p "$scratch_root/vault/2026" "$scratch_root/vault/ref/papers"
trap 'rm -rf -- "$scratch_root"' EXIT

cat > "$scratch_root/config.yml" <<'EOF'
plan:
  exempt: [GTD]
EOF
cat > "$scratch_root/vault/dev.md" <<'EOF'
---
type: "[[area]]"
color: blue
---
# Dev
EOF
cat > "$scratch_root/vault/sase.md" <<'EOF'
---
type: "[[project]]"
parent: "[[dev]]"
---
# Sase

## Tasks

- [ ] #task #ref [[ref/papers/attention]] [created::2026-10-16] ^ref-attention
EOF
cat > "$scratch_root/vault/bob.md" <<'EOF'
---
type: "[[project]]"
parent: "[[dev]]"
---
# Bob

## Tasks

- [ ] #task Do work [created::2026-10-16] ^work
EOF
cat > "$scratch_root/vault/ref/papers/attention.md" <<'EOF'
---
type: "[[ref]]"
status: ready
title: Attention Is All You Need
id: attention
---
# Attention Is All You Need
EOF
cat > "$scratch_root/vault/2026/20261016.md" <<'EOF'
## Pomodoros
- [ ] (**0900-0930** [t:: 30m])
  - [[sase#^ref-attention]]
- [ ] () — HACK
  - [[bob#^work]]
EOF

export BOB_DIR="$scratch_root/vault"
export BOB_CONFIG_FILE="$scratch_root/config.yml"
export BOB_NOW="2026-10-16 09:15:00"

"$bob_bin" ref today attention -d -f json \
  > "$repo_root/Tests/Fixtures/refs-today-homes.json"
"$bob_bin" capture --dry-run -f json -- '=' \
  > "$repo_root/Tests/Fixtures/pomodoro-start-override-unnamed.json"
"$bob_bin" capture-complete -c 2 -f json -- '=#' \
  > "$repo_root/Tests/Fixtures/pomodoro-start-override-complete-unnamed.json"
"$bob_bin" capture-complete -c 3 -f json -- '=3#' \
  > "$repo_root/Tests/Fixtures/pomodoro-start-override-complete-fresh-unnamed.json"

echo "Generated Pomodoro homes fixtures with $($bob_bin --version | head -n 1)"

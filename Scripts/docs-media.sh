#!/usr/bin/env bash
# Import the curated synthetic CI renders with their provenance.
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec python3 "$script_dir/docs_media.py" "$@"

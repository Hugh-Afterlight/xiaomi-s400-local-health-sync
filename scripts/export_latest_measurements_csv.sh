#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

PYTHON="${PYTHON_BIN:-python3}"
"$PYTHON" scripts/export_measurements_csv.py "$@"

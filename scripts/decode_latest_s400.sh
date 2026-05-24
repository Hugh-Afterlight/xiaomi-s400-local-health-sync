#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

PYTHON="$BASE/tools/xiaomi-cloud-tokens-extractor/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  echo "Missing parser environment. Run ./scripts/setup_token_extractor.sh first."
  exit 1
fi

"$PYTHON" scripts/decode_s400_observations.py "$@"

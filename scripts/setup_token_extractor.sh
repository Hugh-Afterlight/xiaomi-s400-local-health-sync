#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

TOOLS_DIR="$BASE/tools"
EXTRACTOR_DIR="$TOOLS_DIR/xiaomi-cloud-tokens-extractor"
REPO_URL="https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor.git"

mkdir -p "$TOOLS_DIR"

if [[ ! -d "$EXTRACTOR_DIR/.git" ]]; then
  git clone "$REPO_URL" "$EXTRACTOR_DIR"
else
  git -C "$EXTRACTOR_DIR" pull --ff-only
fi

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3.12)"
  else
    PYTHON_BIN="$(command -v python3)"
  fi
fi

if [[ ! -d "$EXTRACTOR_DIR/.venv" ]]; then
  "$PYTHON_BIN" -m venv "$EXTRACTOR_DIR/.venv"
fi

source "$EXTRACTOR_DIR/.venv/bin/activate"
python -m pip install --upgrade pip
python -m pip install -r "$EXTRACTOR_DIR/requirements.txt"
python -m pip install "xiaomi-ble>=1.12,<2"

echo "Xiaomi Cloud Tokens Extractor is ready at:"
echo "$EXTRACTOR_DIR"
echo "Run: ./scripts/run_token_extractor.sh"

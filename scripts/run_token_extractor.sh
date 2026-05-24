#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
EXTRACTOR_DIR="$BASE/tools/xiaomi-cloud-tokens-extractor"

if [[ ! -d "$EXTRACTOR_DIR/.venv" ]]; then
  echo "Extractor is not set up yet. Run ./scripts/setup_token_extractor.sh first."
  exit 1
fi

cd "$EXTRACTOR_DIR"
source .venv/bin/activate

OUT_DIR="$BASE/data/private"
OUT_FILE="$OUT_DIR/xiaomi_tokens.json"
mkdir -p "$OUT_DIR"

echo "This tool will ask for Xiaomi account details locally."
echo "Do not paste passwords or extracted keys into chat."
echo "Output JSON will be saved locally to:"
echo "$OUT_FILE"
echo "After it finishes, import the S400 fields with:"
echo "./scripts/import_s400_credentials.py --input data/private/xiaomi_tokens.json"
echo
echo "If you inspect the extractor output manually, look for:"
echo "- MAC"
echo "- BLE KEY"
echo "- TOKEN"
echo "- DID"
echo "- server/region"
echo

python token_extractor.py -o "$OUT_FILE"

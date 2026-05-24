#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

APP_DIR="bin/S400BLEScan.app"
SCANNER="$APP_DIR/Contents/MacOS/s400-ble-scan"
CONFIG="$BASE/config.json"

if [[ ! -x "$SCANNER" ]]; then
  ./scripts/build_scanner.sh
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Missing $CONFIG. Create it from config.example.json before scanning."
  exit 2
fi

open -W -n "$APP_DIR" --args \
  --config "$CONFIG" \
  --output-dir "$BASE/data/ble_observations" \
  --summary-dir "$BASE/data/ble_summaries" \
  "$@"

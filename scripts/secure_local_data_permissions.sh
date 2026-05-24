#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

DIRS=(
  "$BASE/data"
  "$BASE/data/private"
  "$BASE/data/ble_observations"
  "$BASE/data/ble_summaries"
  "$BASE/data/parsed_measurements"
  "$BASE/data/exports"
  "$BASE/logs"
)

for dir in "${DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    chmod 700 "$dir"
    find "$dir" -type d -exec chmod 700 {} +
    find "$dir" -type f -exec chmod 600 {} +
  fi
done

echo "Local private data permissions secured."

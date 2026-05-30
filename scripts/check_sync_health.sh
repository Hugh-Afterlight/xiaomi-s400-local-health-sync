#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

LEDGER="$BASE/data/exports/s400_measurements.csv"
TARGET_DIR="${S400_GOOGLE_DRIVE_EXPORT_DIR:-}"
TARGET_NAME="${S400_GOOGLE_DRIVE_EXPORT_NAME:-s400_measurements.csv}"
TARGET_SUBDIR="${S400_GOOGLE_DRIVE_EXPORT_SUBDIR:-Health Auto Export/S400 Health Data}"
LOG_FILE="$BASE/logs/s400_watch.log"

if [[ -z "$TARGET_DIR" ]]; then
  for ROOT in \
    "$HOME"/Library/CloudStorage/GoogleDrive-*/"我的云端硬盘" \
    "$HOME"/Library/CloudStorage/GoogleDrive-*/"My Drive" \
    "$HOME/Google Drive"
  do
    if [[ -d "$ROOT" ]]; then
      TARGET_DIR="$ROOT/$TARGET_SUBDIR"
      break
    fi
  done
fi

TARGET_FILE="$TARGET_DIR/$TARGET_NAME"

echo "S400 sync health"
echo "Project: $BASE"
echo

if [[ ! -f "$LEDGER" ]]; then
  echo "Local ledger missing: $LEDGER"
  exit 1
fi

local_lines="$(wc -l < "$LEDGER" | tr -d ' ')"
local_rows="$((local_lines > 0 ? local_lines - 1 : 0))"
echo "Local ledger: $LEDGER"
echo "Local rows: $local_rows"

if [[ -z "$TARGET_DIR" || ! -f "$TARGET_FILE" ]]; then
  echo "Google Drive ledger missing."
  echo "Expected: $TARGET_FILE"
  exit 1
fi

drive_lines="$(wc -l < "$TARGET_FILE" | tr -d ' ')"
drive_rows="$((drive_lines > 0 ? drive_lines - 1 : 0))"
echo "Google Drive ledger: $TARGET_FILE"
echo "Google Drive rows: $drive_rows"
echo

if cmp -s "$LEDGER" "$TARGET_FILE"; then
  echo "Sync status: OK, local and Google Drive CSV match."
else
  echo "Sync status: WARNING, local and Google Drive CSV differ."
  echo "Run: ./scripts/sync_ledger_to_google_drive.sh"
  echo
  echo "Recent local ledger rows:"
  tail -5 "$LEDGER"
  echo
  echo "Recent Google Drive rows:"
  tail -5 "$TARGET_FILE"
  exit 1
fi

echo
echo "Recent background sync failures:"
if [[ -f "$LOG_FILE" ]] && grep -E "Capture saved locally but Google Drive sync failed|Google Drive sync failed after" "$LOG_FILE" >/dev/null 2>&1; then
  grep -E "Capture saved locally but Google Drive sync failed|Google Drive sync failed after" "$LOG_FILE" | tail -10
else
  echo "None found."
fi

echo
echo "Latest local measurements:"
tail -5 "$LEDGER"

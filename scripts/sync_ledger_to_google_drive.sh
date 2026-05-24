#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

LEDGER="${1:-$BASE/data/exports/s400_measurements.csv}"
TARGET_DIR="${S400_GOOGLE_DRIVE_EXPORT_DIR:-}"
TARGET_NAME="${S400_GOOGLE_DRIVE_EXPORT_NAME:-s400_measurements.csv}"
EXPECTED_HEADER="measurement_id,measured_at_local,device_label,profile_id,person_label,person_match_method,person_match_confidence,weight_kg,impedance_ohm,impedance_low_ohm,heart_rate_bpm,rssi,packet_count,completeness_score,device_model,parser"

if [[ ! -f "$LEDGER" ]]; then
  echo "Missing ledger: $LEDGER"
  exit 2
fi

HEADER="$(head -n 1 "$LEDGER" | tr -d '\r')"
if [[ "$HEADER" != "$EXPECTED_HEADER" ]]; then
  echo "Refusing to sync unexpected CSV header."
  echo "Only the sanitized measurement ledger may be copied to Google Drive."
  exit 3
fi

if [[ -z "$TARGET_DIR" ]]; then
  for ROOT in \
    "$HOME"/Library/CloudStorage/GoogleDrive-*/"我的云端硬盘" \
    "$HOME"/Library/CloudStorage/GoogleDrive-*/"My Drive" \
    "$HOME/Google Drive"
  do
    if [[ -d "$ROOT" ]]; then
      TARGET_DIR="$ROOT/S400 Health Data"
      break
    fi
  done
fi

if [[ -z "$TARGET_DIR" ]]; then
  echo "Google Drive folder was not found."
  echo "Set S400_GOOGLE_DRIVE_EXPORT_DIR to a local Google Drive folder and retry."
  exit 4
fi

mkdir -p "$TARGET_DIR"
TARGET_FILE="$TARGET_DIR/$TARGET_NAME"
TEMP_FILE="$TARGET_DIR/.${TARGET_NAME}.tmp"

rm -f "$TEMP_FILE"
cp "$LEDGER" "$TARGET_FILE"
chmod 600 "$TARGET_FILE" 2>/dev/null || true

echo "Synced sanitized ledger to: $TARGET_FILE"

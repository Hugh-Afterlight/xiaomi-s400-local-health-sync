#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

LEDGER="${1:-$BASE/data/exports/s400_measurements.csv}"
TARGET_DIR="${S400_GOOGLE_DRIVE_EXPORT_DIR:-}"
TARGET_NAME="${S400_GOOGLE_DRIVE_EXPORT_NAME:-s400_measurements.csv}"
TARGET_SUBDIR="${S400_GOOGLE_DRIVE_EXPORT_SUBDIR:-Health Auto Export/S400 Health Data}"
SYNC_ATTEMPTS="${S400_GOOGLE_DRIVE_SYNC_ATTEMPTS:-5}"
SYNC_RETRY_SECONDS="${S400_GOOGLE_DRIVE_SYNC_RETRY_SECONDS:-5}"
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
      TARGET_DIR="$ROOT/$TARGET_SUBDIR"
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

attempt=1
while (( attempt <= SYNC_ATTEMPTS )); do
  rm -f "$TEMP_FILE" 2>/dev/null || true
  if cp "$LEDGER" "$TEMP_FILE"; then
    chmod 600 "$TEMP_FILE" 2>/dev/null || true
  else
    rm -f "$TEMP_FILE" 2>/dev/null || true
    if (( attempt < SYNC_ATTEMPTS )); then
      echo "Google Drive sync attempt ${attempt}/${SYNC_ATTEMPTS} failed. Retrying in ${SYNC_RETRY_SECONDS}s..." >&2
      sleep "$SYNC_RETRY_SECONDS"
    fi
    attempt=$((attempt + 1))
    continue
  fi

  if mv -f "$TEMP_FILE" "$TARGET_FILE"; then
    chmod 600 "$TARGET_FILE" 2>/dev/null || true
    echo "Synced sanitized ledger to: $TARGET_FILE"
    exit 0
  fi

  rm -f "$TEMP_FILE" 2>/dev/null || true
  if (( attempt < SYNC_ATTEMPTS )); then
    echo "Google Drive sync attempt ${attempt}/${SYNC_ATTEMPTS} failed. Retrying in ${SYNC_RETRY_SECONDS}s..." >&2
    sleep "$SYNC_RETRY_SECONDS"
  fi
  attempt=$((attempt + 1))
done

echo "Google Drive sync failed after ${SYNC_ATTEMPTS} attempts: $TARGET_FILE" >&2
exit 1

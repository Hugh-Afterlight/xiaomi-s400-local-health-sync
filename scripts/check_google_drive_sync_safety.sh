#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

TARGET_DIR="${S400_GOOGLE_DRIVE_EXPORT_DIR:-}"
TARGET_NAME="${S400_GOOGLE_DRIVE_EXPORT_NAME:-s400_measurements.csv}"
TARGET_SUBDIR="${S400_GOOGLE_DRIVE_EXPORT_SUBDIR:-Health Auto Export/S400 Health Data}"
ALLOWED_NAMES=("$TARGET_NAME" "s400_official_reports.csv")
DISALLOWED_FIELDS=(real_mac bind_key token service_data manufacturer_data corebluetooth_id parser_bind_key_fingerprint)

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

if [[ -z "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
  echo "Google Drive S400 export folder was not found."
  exit 2
fi

unexpected=0
for file in "$TARGET_DIR"/*(.N); do
  name="$(basename "$file")"
  if (( ${ALLOWED_NAMES[(Ie)$name]} == 0 )); then
    echo "Unexpected file in Google Drive export folder: $file"
    unexpected=1
  fi
done

if (( unexpected )); then
  exit 3
fi

EXPECTED_FILE="$TARGET_DIR/$TARGET_NAME"
if [[ ! -f "$EXPECTED_FILE" ]]; then
  echo "Missing expected Google Drive CSV: $EXPECTED_FILE"
  exit 4
fi

for file in "$TARGET_DIR"/*(.N); do
  HEADER="$(head -n 1 "$file" | tr -d '\r')"
  for field in "${DISALLOWED_FIELDS[@]}"; do
    if [[ ",$HEADER," == *",$field,"* ]]; then
      echo "Unsafe field found in Google Drive CSV header: $field"
      exit 5
    fi
  done
done

echo "Google Drive sync safety check OK: $TARGET_DIR"

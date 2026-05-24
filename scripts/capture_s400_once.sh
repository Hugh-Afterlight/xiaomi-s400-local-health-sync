#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

DURATION="${1:-75}"
LABEL="${2:-s400-capture}"
MARKER="$(mktemp)"
OBSERVATION=""
PARSED=""
MEASUREMENT_SAVED=0
touch "$MARKER"

delete_newer_than_marker() {
  local dir="$1"
  local pattern="$2"
  if [[ -d "$dir" && -f "$MARKER" ]]; then
    find "$dir" -type f -name "$pattern" -newer "$MARKER" -print0 2>/dev/null | xargs -0 rm -f
  fi
}

cleanup_on_exit() {
  local exit_code=$?
  if [[ "$exit_code" -ne 0 && "$MEASUREMENT_SAVED" != "1" && "${S400_DISCARD_FAILED_CAPTURE:-0}" == "1" ]]; then
    delete_newer_than_marker "$BASE/data/ble_observations" "*.jsonl"
    delete_newer_than_marker "$BASE/data/ble_summaries" "*.summary.json"
    delete_newer_than_marker "$BASE/data/parsed_measurements" "s400_measurements_*.jsonl"
    delete_newer_than_marker "$BASE/data/exports" "s400_measurements_*.csv"
  fi
  ./scripts/secure_local_data_permissions.sh >/dev/null 2>&1 || true
  rm -f "$MARKER"
}
trap cleanup_on_exit EXIT

echo "Starting S400 capture for ${DURATION}s."
echo "Step on the scale now and stay until measurement finishes."

./scripts/run_scan_once.sh --duration "$DURATION" --label "$LABEL"

OBSERVATION="$(
  find "$BASE/data/ble_observations" -type f -name '*.jsonl' -newer "$MARKER" -print0 \
    | xargs -0 ls -t 2>/dev/null \
    | head -1
)"

if [[ -z "${OBSERVATION:-}" ]]; then
  echo "No new BLE observation file found."
  exit 1
fi

echo "Decoding observation: $OBSERVATION"
if ! DECODE_OUTPUT="$(./scripts/decode_latest_s400.sh --input "$OBSERVATION")"; then
  echo "$DECODE_OUTPUT"
  exit 1
fi
echo "$DECODE_OUTPUT"

PARSED="$(
  printf '%s\n' "$DECODE_OUTPUT" | awk -F'Output: ' '/^Output: / {print $2}' | tail -1
)"
if [[ -z "${PARSED:-}" ]]; then
  echo "Decoder did not report a parsed measurement output file."
  exit 1
fi

./scripts/export_latest_measurements_csv.sh --input "$PARSED"
python3 scripts/append_measurement_ledger.py --input "$PARSED"
MEASUREMENT_SAVED=1
if ! ./scripts/sync_ledger_to_google_drive.sh; then
  echo "Error: Google Drive sync failed. Local ledger was saved, but cloud sync did not complete."
  exit 1
fi

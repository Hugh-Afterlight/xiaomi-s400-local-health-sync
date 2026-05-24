#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

RAW_DAYS="${S400_KEEP_RAW_DAYS:-30}"
PARSED_DAYS="${S400_KEEP_PARSED_DAYS:-30}"
RUN_CSV_DAYS="${S400_KEEP_RUN_CSV_DAYS:-365}"
TEMP_LOG_DAYS="${S400_KEEP_TEMP_LOG_DAYS:-1}"

delete_old_files() {
  local dir="$1"
  local pattern="$2"
  local days="$3"
  local label="$4"
  if [[ ! -d "$dir" ]]; then
    return
  fi
  local count
  count="$(find "$dir" -type f -name "$pattern" -mtime +"$days" -print 2>/dev/null | wc -l | tr -d ' ')"
  find "$dir" -type f -name "$pattern" -mtime +"$days" -print0 2>/dev/null | xargs -0 rm -f
  echo "Cleanup: removed ${count} ${label} older than ${days} days."
}

delete_old_files "$BASE/data/ble_observations" "*.jsonl" "$RAW_DAYS" "raw observation files"
delete_old_files "$BASE/data/ble_summaries" "*.summary.json" "$RAW_DAYS" "summary files"
delete_old_files "$BASE/data/parsed_measurements" "s400_measurements_*.jsonl" "$PARSED_DAYS" "parsed measurement files"
delete_old_files "$BASE/data/exports" "s400_measurements_*.csv" "$RUN_CSV_DAYS" "per-run CSV exports"
delete_old_files "$BASE/logs" "s400_capture.*" "$TEMP_LOG_DAYS" "temporary capture logs"

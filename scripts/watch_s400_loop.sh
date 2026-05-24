#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

SCAN_SECONDS="${S400_WATCH_SCAN_SECONDS:-90}"
SLEEP_SECONDS="${S400_WATCH_SLEEP_SECONDS:-10}"
LOG_DIR="${S400_WATCH_LOG_DIR:-$BASE/logs}"
LOG_FILE="${S400_WATCH_LOG_FILE:-$LOG_DIR/s400_watch.log}"
MAX_LOG_BYTES="${S400_WATCH_MAX_LOG_BYTES:-1048576}"
CLEANUP_INTERVAL_SECONDS="${S400_CLEANUP_INTERVAL_SECONDS:-3600}"
CAPTURE_TIMEOUT_SECONDS="${S400_CAPTURE_TIMEOUT_SECONDS:-$((SCAN_SECONDS + 90))}"
ACTIVE_START_HOUR="${S400_ACTIVE_START_HOUR:-5}"
ACTIVE_END_HOUR="${S400_ACTIVE_END_HOUR:-9}"
LAST_CLEANUP=0

mkdir -p "$LOG_DIR"

rotate_log_if_needed() {
  if [[ -f "$LOG_FILE" ]]; then
    local size
    size="$(wc -c < "$LOG_FILE" | tr -d ' ')"
    if (( size > MAX_LOG_BYTES )); then
      mv "$LOG_FILE" "$LOG_FILE.1"
    fi
  fi
}

log_line() {
  rotate_log_if_needed
  print "[$(date -Iseconds)] $*" >> "$LOG_FILE"
}

log_matching_lines() {
  local file="$1"
  local pattern="$2"
  grep -E "$pattern" "$file" 2>/dev/null | while IFS= read -r line; do
    log_line "$line"
  done
}

run_periodic_cleanup() {
  local now
  now="$(date +%s)"
  if (( now - LAST_CLEANUP < CLEANUP_INTERVAL_SECONDS )); then
    return
  fi
  LAST_CLEANUP="$now"
  if ./scripts/cleanup_s400_artifacts.sh >> "$LOG_FILE" 2>&1; then
    log_line "Cleanup completed."
  else
    log_line "Warning: cleanup failed."
  fi
}

seconds_since_midnight() {
  local hour minute second
  hour="$(date +%H)"
  minute="$(date +%M)"
  second="$(date +%S)"
  echo $((10#$hour * 3600 + 10#$minute * 60 + 10#$second))
}

active_window_bounds() {
  echo $((ACTIVE_START_HOUR * 3600)) $((ACTIVE_END_HOUR * 3600))
}

is_active_window() {
  local now start end
  now="$(seconds_since_midnight)"
  read -r start end <<< "$(active_window_bounds)"
  if (( start < end )); then
    (( now >= start && now < end ))
  else
    (( now >= start || now < end ))
  fi
}

seconds_until_window_end() {
  local now start end target
  now="$(seconds_since_midnight)"
  read -r start end <<< "$(active_window_bounds)"
  target="$end"
  if (( start >= end && now >= start )); then
    target="$((end + 86400))"
  fi
  echo $((target - now))
}

run_capture_with_timeout() {
  local label="$1"
  local run_log="$2"
  S400_DISCARD_FAILED_CAPTURE=1 ./scripts/capture_s400_once.sh "$SCAN_SECONDS" "$label" > "$run_log" 2>&1 &
  local pid="$!"
  local deadline="$(( $(date +%s) + CAPTURE_TIMEOUT_SECONDS ))"

  while kill -0 "$pid" 2>/dev/null; do
    if (( $(date +%s) >= deadline )); then
      print "Capture timed out after ${CAPTURE_TIMEOUT_SECONDS}s." >> "$run_log"
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
      pkill -f "$BASE/bin/S400BLEScan.app/Contents/MacOS/s400-ble-scan" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
  done

  wait "$pid"
}

if ! is_active_window; then
  log_line "Outside active window ${ACTIVE_START_HOUR}:00-${ACTIVE_END_HOUR}:00. Exiting until next scheduled launch."
  exit 0
fi

log_line "S400 watch loop started. active=${ACTIVE_START_HOUR}:00-${ACTIVE_END_HOUR}:00 scan=${SCAN_SECONDS}s sleep=${SLEEP_SECONDS}s timeout=${CAPTURE_TIMEOUT_SECONDS}s"

while true; do
  if ! is_active_window; then
    log_line "Active window ended. Exiting."
    exit 0
  fi
  remaining="$(seconds_until_window_end)"
  if (( remaining <= 0 )); then
    log_line "Active window ended. Exiting."
    exit 0
  fi
  if (( remaining < SCAN_SECONDS )); then
    log_line "Less than one full scan window remains (${remaining}s). Exiting."
    exit 0
  fi
  LABEL="auto-$(date +%Y%m%d-%H%M%S)"
  RUN_LOG="$(mktemp "$LOG_DIR/s400_capture.XXXXXX")"
  log_line "Starting capture window: $LABEL"
  if run_capture_with_timeout "$LABEL" "$RUN_LOG"; then
    log_line "Capture completed: $LABEL"
    log_matching_lines "$RUN_LOG" "Measurement:|Appended rows:|Synced sanitized ledger to:"
  else
    if grep -q "Capture timed out" "$RUN_LOG" 2>/dev/null; then
      log_line "Capture timed out: $LABEL"
    elif grep -q "No decoded measurements found." "$RUN_LOG" 2>/dev/null; then
      log_line "No complete measurement captured: $LABEL"
    elif grep -q "Google Drive sync failed" "$RUN_LOG" 2>/dev/null; then
      log_line "Capture saved locally but Google Drive sync failed: $LABEL"
      tail -20 "$RUN_LOG" | while IFS= read -r line; do
        log_line "  $line"
      done
    else
      log_line "Capture failed: $LABEL"
      tail -20 "$RUN_LOG" | while IFS= read -r line; do
        log_line "  $line"
      done
    fi
  fi
  rm -f "$RUN_LOG"
  run_periodic_cleanup
  sleep "$SLEEP_SECONDS"
done

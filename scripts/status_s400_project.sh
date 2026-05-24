#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

LABEL="com.hugh.s400-watch"
LEDGER="$BASE/data/exports/s400_measurements.csv"
STATUS_LOG="$BASE/logs/s400_watch.log"

echo "S400 project status"
echo "Project: $BASE"
echo

echo "Background service:"
if launchctl print "gui/$(id -u)/${LABEL}" >/tmp/s400_launch_status.$$ 2>/dev/null; then
  grep -E 'state =|pid =|last exit code|runs =' /tmp/s400_launch_status.$$ || true
else
  echo "not installed or not running"
fi
rm -f /tmp/s400_launch_status.$$
echo

echo "Secrets:"
./scripts/check_secrets.py || true
echo

echo "Local ledger:"
if [[ -f "$LEDGER" ]]; then
  rows="$(($(wc -l < "$LEDGER" | tr -d ' ') - 1))"
  if (( rows < 0 )); then rows=0; fi
  echo "$LEDGER"
  echo "measurement rows: $rows"
else
  echo "missing: $LEDGER"
fi
echo

echo "Google Drive sync:"
if ./scripts/check_google_drive_sync_safety.sh; then
  :
else
  echo "Google Drive sync safety check failed."
fi
echo

echo "Recent watch log:"
if [[ -f "$STATUS_LOG" ]]; then
  tail -12 "$STATUS_LOG"
else
  echo "missing: $STATUS_LOG"
fi

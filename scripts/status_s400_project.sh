#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

LABEL="com.hugh.s400-watch"
LEDGER="$BASE/data/exports/s400_measurements.csv"
STATUS_LOG="$BASE/logs/s400_watch.log"
PROFILES="$BASE/profiles.local.csv"

echo "S400 project status"
echo "Project: $BASE"
echo

echo "Background service:"
if launchctl print "gui/$(id -u)/${LABEL}" >/tmp/s400_launch_status.$$ 2>/dev/null; then
  grep -E 'state =|pid =|last exit code|runs =' /tmp/s400_launch_status.$$ || true
  echo "active window: 05:00-09:00 local time; not running outside this window is normal"
else
  echo "not installed or not running"
fi
rm -f /tmp/s400_launch_status.$$
echo

echo "Official report extractor:"
REPORT_LABEL="com.hugh.s400-report-extract"
if launchctl print "gui/$(id -u)/${REPORT_LABEL}" >/tmp/s400_report_launch_status.$$ 2>/dev/null; then
  grep -E 'state =|pid =|last exit code|runs =' /tmp/s400_report_launch_status.$$ || true
  echo "schedule: daily at 09:00 local time"
else
  echo "not installed"
fi
rm -f /tmp/s400_report_launch_status.$$
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

echo "Family profile matching:"
if [[ -f "$PROFILES" ]]; then
  echo "$PROFILES"
  tail -n +2 "$PROFILES" | while IFS=, read -r person min_weight max_weight notes; do
    if [[ -n "$person" ]]; then
      echo "- $person: ${min_weight}-${max_weight} kg"
    fi
  done
else
  echo "missing: $PROFILES"
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

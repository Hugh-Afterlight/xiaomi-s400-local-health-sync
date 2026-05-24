#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

echo "Verifying S400 project..."

zsh -n scripts/*.sh
python3 -m py_compile scripts/*.py

for file in config.example.json secrets.local.example.json config.json secrets.local.json; do
  python3 -m json.tool "$file" >/dev/null
done

./scripts/build_scanner.sh
./scripts/check_secrets.py
./scripts/sync_ledger_to_google_drive.sh
./scripts/check_google_drive_sync_safety.sh
./scripts/cleanup_s400_artifacts.sh
./scripts/secure_local_data_permissions.sh

latest_parsed="$(ls -t data/parsed_measurements/s400_measurements_*.jsonl 2>/dev/null | head -1 || true)"
if [[ -n "$latest_parsed" ]]; then
  before="$(wc -l < data/exports/s400_measurements.csv | tr -d ' ')"
  python3 scripts/append_measurement_ledger.py --input "$latest_parsed" >/tmp/s400_verify_append.$$
  after="$(wc -l < data/exports/s400_measurements.csv | tr -d ' ')"
  rm -f /tmp/s400_verify_append.$$
  if [[ "$before" != "$after" ]]; then
    echo "Ledger duplicate check failed: row count changed from $before to $after"
    exit 1
  fi
  echo "Ledger duplicate check OK."
fi

if launchctl print "gui/$(id -u)/com.hugh.s400-watch" >/dev/null 2>&1; then
  echo "LaunchAgent is installed and running."
else
  echo "Warning: LaunchAgent is not running. Start it with ./scripts/install_s400_launch_agent.sh"
fi

echo "Verification complete."

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

SCANNER="bin/S400BLEScan.app/Contents/MacOS/s400-ble-scan"
INFO_PLIST="bin/S400BLEScan.app/Contents/Info.plist"
if [[ ! -x "$SCANNER" || src/S400BLEScan/main.swift -nt "$SCANNER" || src/S400BLEScan/BluetoothUsage.plist -nt "$INFO_PLIST" ]]; then
  ./scripts/build_scanner.sh
else
  echo "Scanner build is current."
fi
./scripts/check_secrets.py

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

./scripts/sync_ledger_to_google_drive.sh
./scripts/check_google_drive_sync_safety.sh
./scripts/cleanup_s400_artifacts.sh
./scripts/secure_local_data_permissions.sh

if launchctl print "gui/$(id -u)/com.hugh.s400-watch" >/tmp/s400_verify_launch.$$ 2>/dev/null; then
  state="$(grep -E 'state =' /tmp/s400_verify_launch.$$ | head -1 | sed 's/^[[:space:]]*//')"
  rm -f /tmp/s400_verify_launch.$$
  echo "LaunchAgent is installed (${state}; active window is 05:00-09:00)."
else
  rm -f /tmp/s400_verify_launch.$$
  echo "Warning: LaunchAgent is not running. Start it with ./scripts/install_s400_launch_agent.sh"
fi

echo "Verification complete."

#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

WITH_TOKEN_EXTRACTOR=false
SKIP_BUILD=false

usage() {
  cat <<'USAGE'
Usage: ./scripts/bootstrap_new_machine.sh [--with-token-extractor] [--skip-build]

Creates local config files when missing, prepares private data folders,
builds the BLE scanner app, and optionally installs the Xiaomi token extractor.

Use this after cloning the private repo on a new Mac. If you already have an
encrypted private-state backup, run restore_private_state.sh after this script.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-token-extractor)
      WITH_TOKEN_EXTRACTOR=true
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

copy_if_missing() {
  local source_file="$1"
  local target_file="$2"

  if [[ -f "$target_file" ]]; then
    echo "Keeping existing $target_file"
  else
    cp "$source_file" "$target_file"
    chmod 600 "$target_file"
    echo "Created $target_file"
  fi
}

mkdir -p \
  "$BASE/data/private" \
  "$BASE/data/ble_observations" \
  "$BASE/data/ble_summaries" \
  "$BASE/data/parsed_measurements" \
  "$BASE/data/exports" \
  "$BASE/logs"

copy_if_missing "$BASE/config.example.json" "$BASE/config.json"
copy_if_missing "$BASE/secrets.local.example.json" "$BASE/secrets.local.json"
copy_if_missing "$BASE/profiles.local.example.csv" "$BASE/profiles.local.csv"

if [[ "$SKIP_BUILD" == false ]]; then
  ./scripts/build_scanner.sh
else
  echo "Skipped scanner build."
fi

if [[ "$WITH_TOKEN_EXTRACTOR" == true ]]; then
  ./scripts/setup_token_extractor.sh
else
  echo "Skipped token extractor setup. Use --with-token-extractor if needed."
fi

./scripts/secure_local_data_permissions.sh

cat <<'DONE'

Bootstrap complete.

Next steps:
1. Restore private state if you have a backup:
   ./scripts/restore_private_state.sh /path/to/s400-private-state-YYYYMMDD-HHMMSS.tar.gz.enc
2. Grant Bluetooth permission when macOS asks.
3. Run:
   ./scripts/verify_s400_project.sh
4. Install the scheduled watcher when ready:
   ./scripts/install_s400_launch_agent.sh
DONE

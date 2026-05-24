#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

TARGET_DIR="$BASE"
BACKUP_PATH=""
PASSPHRASE="${S400_BACKUP_PASSPHRASE:-}"

usage() {
  cat <<'USAGE'
Usage: ./scripts/restore_private_state.sh [--target-dir DIR] /path/to/s400-private-state-YYYYMMDD-HHMMSS.tar.gz.enc

Restores encrypted private state created by backup_private_state.sh.
By default it restores into this project directory.

Set S400_BACKUP_PASSPHRASE for non-interactive use, or run from a terminal
and enter the passphrase when prompted.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir)
      if [[ $# -lt 2 ]]; then
        echo "--target-dir needs a directory path." >&2
        exit 2
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$BACKUP_PATH" ]]; then
        echo "Only one backup file can be restored at a time." >&2
        exit 2
      fi
      BACKUP_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$BACKUP_PATH" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -f "$BACKUP_PATH" ]]; then
  echo "Backup file not found: $BACKUP_PATH" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required but was not found." >&2
  exit 1
fi

if [[ -z "$PASSPHRASE" ]]; then
  if [[ -t 0 ]]; then
    echo -n "Backup passphrase: "
    read -rs PASSPHRASE
    echo
  else
    echo "Set S400_BACKUP_PASSPHRASE or run from an interactive terminal." >&2
    exit 2
  fi
fi

if [[ -z "$PASSPHRASE" ]]; then
  echo "Passphrase cannot be empty." >&2
  exit 2
fi

WORKDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

TAR_PATH="$WORKDIR/state.tar.gz"
STATE_DIR="$WORKDIR/state"
mkdir -p "$STATE_DIR"

export S400_BACKUP_PASSPHRASE="$PASSPHRASE"
if ! openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -in "$BACKUP_PATH" \
  -out "$TAR_PATH" \
  -pass env:S400_BACKUP_PASSPHRASE; then
  unset S400_BACKUP_PASSPHRASE
  echo "Could not decrypt backup. Check the passphrase and file path." >&2
  exit 1
fi
unset S400_BACKUP_PASSPHRASE

tar -C "$STATE_DIR" -xzf "$TAR_PATH"

for required in config.json profiles.local.csv secrets.local.json; do
  if [[ ! -f "$STATE_DIR/$required" ]]; then
    echo "Backup is missing required file: $required" >&2
    exit 1
  fi
done

mkdir -p "$TARGET_DIR/data/exports"

install -m 600 "$STATE_DIR/config.json" "$TARGET_DIR/config.json"
install -m 600 "$STATE_DIR/profiles.local.csv" "$TARGET_DIR/profiles.local.csv"
install -m 600 "$STATE_DIR/secrets.local.json" "$TARGET_DIR/secrets.local.json"

if [[ -f "$STATE_DIR/data/exports/s400_measurements.csv" ]]; then
  install -m 600 "$STATE_DIR/data/exports/s400_measurements.csv" "$TARGET_DIR/data/exports/s400_measurements.csv"
fi

mkdir -p \
  "$TARGET_DIR/data/private" \
  "$TARGET_DIR/data/ble_observations" \
  "$TARGET_DIR/data/ble_summaries" \
  "$TARGET_DIR/data/parsed_measurements" \
  "$TARGET_DIR/logs"

chmod 700 "$TARGET_DIR/data" "$TARGET_DIR/logs" 2>/dev/null || true
find "$TARGET_DIR/data" -type d -exec chmod 700 {} + 2>/dev/null || true
find "$TARGET_DIR/data" -type f -exec chmod 600 {} + 2>/dev/null || true
find "$TARGET_DIR/logs" -type d -exec chmod 700 {} + 2>/dev/null || true
find "$TARGET_DIR/logs" -type f -exec chmod 600 {} + 2>/dev/null || true

echo "Private state restored into:"
echo "$TARGET_DIR"
echo
echo "Restored files:"
echo "- config.json"
echo "- profiles.local.csv"
echo "- secrets.local.json"
if [[ -f "$TARGET_DIR/data/exports/s400_measurements.csv" ]]; then
  echo "- data/exports/s400_measurements.csv"
fi
echo
echo "On a new Mac, rebuild the scanner, grant Bluetooth permission, then run:"
echo "./scripts/verify_s400_project.sh"

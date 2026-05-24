#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

DEFAULT_BACKUP_DIR=""
for candidate in "$HOME"/Library/CloudStorage/GoogleDrive-*/"我的云端硬盘"/"Health Auto Export"/"S400 Health Data"/private-backups; do
  DEFAULT_BACKUP_DIR="$candidate"
  break
done

if [[ -z "$DEFAULT_BACKUP_DIR" ]]; then
  DEFAULT_BACKUP_DIR="$BASE/private-backups"
fi

BACKUP_DIR="${S400_BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
PASSPHRASE="${S400_BACKUP_PASSPHRASE:-}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="s400-private-state-${TIMESTAMP}.tar.gz.enc"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

usage() {
  cat <<'USAGE'
Usage: ./scripts/backup_private_state.sh

Creates an encrypted backup of the private state needed to restore this project
on another Mac. Set S400_BACKUP_DIR to override the backup folder.

Passphrase:
- Interactive terminal: the script prompts for it.
- Automation/test: set S400_BACKUP_PASSPHRASE in the environment.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
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
    echo -n "Confirm passphrase: "
    read -rs CONFIRM_PASSPHRASE
    echo
    if [[ "$PASSPHRASE" != "$CONFIRM_PASSPHRASE" ]]; then
      echo "Passphrases do not match." >&2
      exit 2
    fi
  else
    echo "Set S400_BACKUP_PASSPHRASE or run from an interactive terminal." >&2
    exit 2
  fi
fi

if [[ -z "$PASSPHRASE" ]]; then
  echo "Passphrase cannot be empty." >&2
  exit 2
fi

required_files=(
  "$BASE/config.json"
  "$BASE/profiles.local.csv"
  "$BASE/secrets.local.json"
)

missing_files=()
for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    missing_files+=("${file#$BASE/}")
  fi
done

if (( ${#missing_files[@]} > 0 )); then
  echo "Cannot create backup. Missing required files:" >&2
  for file in "${missing_files[@]}"; do
    echo "- $file" >&2
  done
  exit 1
fi

WORKDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

STATE_DIR="$WORKDIR/state"
mkdir -p "$STATE_DIR/data/exports"

install -m 600 "$BASE/config.json" "$STATE_DIR/config.json"
install -m 600 "$BASE/profiles.local.csv" "$STATE_DIR/profiles.local.csv"
install -m 600 "$BASE/secrets.local.json" "$STATE_DIR/secrets.local.json"

if [[ -f "$BASE/data/exports/s400_measurements.csv" ]]; then
  install -m 600 "$BASE/data/exports/s400_measurements.csv" "$STATE_DIR/data/exports/s400_measurements.csv"
fi

cat > "$STATE_DIR/MANIFEST.txt" <<MANIFEST
Xiaomi S400 private state backup
created_at=$TIMESTAMP
contains=config.json,profiles.local.csv,secrets.local.json,data/exports/s400_measurements.csv_if_present
excludes=data/private,raw_ble_observations,logs,tools,bin
MANIFEST
chmod 600 "$STATE_DIR/MANIFEST.txt"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR" 2>/dev/null || true

TAR_PATH="$WORKDIR/state.tar.gz"
tar -C "$STATE_DIR" -czf "$TAR_PATH" .

export S400_BACKUP_PASSPHRASE="$PASSPHRASE"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -in "$TAR_PATH" \
  -out "$BACKUP_PATH" \
  -pass env:S400_BACKUP_PASSPHRASE
unset S400_BACKUP_PASSPHRASE

chmod 600 "$BACKUP_PATH" 2>/dev/null || true

SHA256="$(shasum -a 256 "$BACKUP_PATH" | awk '{print $1}')"
cat > "$BACKUP_DIR/LATEST.txt" <<LATEST
latest_backup=$BACKUP_NAME
created_at=$TIMESTAMP
sha256=$SHA256
LATEST
chmod 600 "$BACKUP_DIR/LATEST.txt" 2>/dev/null || true

echo "Encrypted private-state backup created:"
echo "$BACKUP_PATH"
echo "SHA256: $SHA256"
echo
echo "Keep the passphrase outside this repo. Without it, the backup cannot be restored."

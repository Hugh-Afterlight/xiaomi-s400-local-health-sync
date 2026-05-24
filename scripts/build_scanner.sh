#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

mkdir -p bin
APP_DIR="bin/S400BLEScan.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
mkdir -p "$MACOS_DIR"

swiftc \
  -framework Foundation \
  -framework CoreBluetooth \
  src/S400BLEScan/main.swift \
  -o "$MACOS_DIR/s400-ble-scan"

cp src/S400BLEScan/BluetoothUsage.plist "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1

echo "Built $APP_DIR"

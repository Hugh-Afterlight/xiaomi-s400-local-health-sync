#!/bin/zsh
set -euo pipefail

LABEL="com.hugh.s400-watch"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

echo "Stopped and removed LaunchAgent: $LABEL"

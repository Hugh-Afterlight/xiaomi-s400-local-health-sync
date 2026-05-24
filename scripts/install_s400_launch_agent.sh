#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.hugh.s400-watch"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
OUT_LOG="$BASE/logs/s400_watch.launchd.out.log"
ERR_LOG="$BASE/logs/s400_watch.launchd.err.log"
STATUS_LOG="$BASE/logs/s400_watch.log"

mkdir -p "$HOME/Library/LaunchAgents" "$BASE/logs"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${BASE}/scripts/watch_s400_loop.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${BASE}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${OUT_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${ERR_LOG}</string>
</dict>
</plist>
PLIST

chmod 644 "$PLIST"
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/${LABEL}"

echo "Installed and started LaunchAgent: $LABEL"
echo "Plist: $PLIST"
echo "Status log: $STATUS_LOG"
echo "Launchd logs: $OUT_LOG and $ERR_LOG"

#!/bin/zsh
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.hugh.s400-report-extract"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
OUT_LOG="$BASE/logs/s400_report_extract.launchd.out.log"
ERR_LOG="$BASE/logs/s400_report_extract.launchd.err.log"

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
    <string>-lc</string>
    <string>cd "${BASE}" &amp;&amp; ./scripts/extract_xiaomi_report_images.py</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${BASE}</string>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
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

echo "Installed LaunchAgent: $LABEL"
echo "Schedule: daily at 09:00 local time"
echo "Plist: $PLIST"
echo "Launchd logs: $OUT_LOG and $ERR_LOG"

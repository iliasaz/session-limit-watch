#!/bin/bash
# install.sh <target-session-name> [interval-seconds=300]  — installs and loads the launchd job
set -eu
NAME="${1:?target session name required}"; INTERVAL="${2:-300}"
SCRIPT="$HOME/.claude/skills/session-limit-watch/scripts/limit-watch.sh"
LABEL="com.claude.session-limit-watch.$NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="$HOME/.local/state/session-limit-watch/$NAME"
mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents"; chmod +x "$SCRIPT"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$SCRIPT</string><string>$NAME</string></array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$STATE_DIR/launchd.out</string>
  <key>StandardErrorPath</key><string>$STATE_DIR/launchd.err</string>
</dict>
</plist>
PL
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "installed $LABEL (every ${INTERVAL}s) -> $PLIST"
echo "state: $STATE_DIR/state   log: $STATE_DIR/log"

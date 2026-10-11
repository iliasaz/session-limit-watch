#!/bin/bash
# uninstall.sh <target-session-name>
set -eu
NAME="${1:?target session name required}"
PLIST="$HOME/Library/LaunchAgents/com.claude.session-limit-watch.$NAME.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "removed watch for '$NAME' (state/log kept in ~/.local/state/session-limit-watch/$NAME)"

#!/bin/bash
# test.sh <target-session-name> — forces the limited state and runs one tick through launchd.
# Sends ONE real resume ping to the target (it says to ignore it if not interrupted).
set -eu
NAME="${1:?target session name required}"
S="$HOME/.local/state/session-limit-watch/$NAME"; mkdir -p "$S"
echo "limited $(date +%s)" > "$S/state"
launchctl kickstart -k "gui/$(id -u)/com.claude.session-limit-watch.$NAME"
sleep 20
echo "state after: $(cat "$S/state")"; tail -2 "$S/log"

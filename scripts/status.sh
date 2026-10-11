#!/bin/bash
# status.sh <target-session-name>
NAME="${1:?target session name required}"
S="$HOME/.local/state/session-limit-watch/$NAME"
echo "launchd: $(launchctl list 2>/dev/null | /usr/bin/grep "session-limit-watch.$NAME" || echo 'not loaded')"
echo "state:   $(cat "$S/state" 2>/dev/null || echo '(none)')"
echo "target:  $(claude agents --json 2>/dev/null | python3 -I -c 'import json,sys,os
for a in json.load(sys.stdin):
    if a.get("name")==sys.argv[1]: print(a.get("status"), "pid", a.get("pid")); break
else: print("not running")' "$NAME")"
echo "log tail:"; tail -5 "$S/log" 2>/dev/null

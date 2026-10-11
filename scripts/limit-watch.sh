#!/bin/bash
# session-limit-watch: when the Claude usage limit stops a Claude Code session, wait for the
# reset and prompt a fresh headless claude session to tell that session to continue.
# Usage: limit-watch.sh <target-session-name>     (run by launchd every N seconds)
set -u
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
TARGET_NAME="${1:?target session name required}"
MODEL="${LIMIT_WATCH_MODEL:-claude-haiku-4-5-20251001}"
STATE_DIR="$HOME/.local/state/session-limit-watch/$TARGET_NAME"
STATE="$STATE_DIR/state"          # "ok" or "limited <epoch>"
LOG="$STATE_DIR/log"
ZMX=/Applications/supacode.app/Contents/Resources/zmx/zmx   # Supacode's multiplexer; optional
mkdir -p "$STATE_DIR"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
if ! mkdir "$STATE_DIR/lock" 2>/dev/null; then log "skip: previous run still active"; exit 0; fi
trap 'rmdir "$STATE_DIR/lock"' EXIT
[ -f "$STATE" ] || echo ok > "$STATE"
state=$(cut -d' ' -f1 "$STATE")

# 1. Find the target claude process (and its zmx session, if it runs inside Supacode).
agents=$(claude agents --json 2>/dev/null || echo '[]')
pid=$(printf '%s' "$agents" | TARGET="$TARGET_NAME" python3 -I -c '
import json,os,sys
for a in json.load(sys.stdin):
    if a.get("name")==os.environ["TARGET"]: print(a.get("pid","")); break' 2>/dev/null)
if [ -z "$pid" ]; then log "session '$TARGET_NAME' not running; nothing to do"; exit 0; fi
zname=""; p="$pid"
for _ in 1 2 3 4 5 6; do
  cmd=$(ps -o command= -p "$p" 2>/dev/null)
  case "$cmd" in *"zmx attach "*) zname=$(printf '%s' "$cmd" | sed -E 's/.*zmx attach ([^ ]+).*/\1/'); break;; esac
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); [ -n "$p" ] && [ "$p" != 1 ] || break
done

# 2. $0 detection: the limit banner on the target's live screen (Supacode/zmx only).
#    Other terminals: set the state by hand or via `limit-watch.sh <name>` after writing
#    "limited <epoch>" to $STATE; the ping path below needs no terminal access.
banner=""
if [ -n "$zname" ] && [ -x "$ZMX" ]; then
  banner=$("$ZMX" history "$zname" 2>/dev/null | tail -40 | /usr/bin/grep -E -o "Usage limit reached.{0,60}|You.ve hit your limit|usage limit.{0,40}resets.{0,30}" | head -1)
fi
if [ "$state" = ok ] && [ -n "$banner" ]; then
  echo "limited $(date +%s)" > "$STATE"; state=limited
  log "limit detected on '$TARGET_NAME' screen: '$banner' (zmx $zname)"
fi
if [ "$state" = ok ]; then exit 0; fi

# 3. Limited: prompt a fresh claude session to tell the target to continue.
#    While the limit holds this fails without cost; the first success is the reset.
PROMPT="You are an automated resume ping that the user set up (session-limit-watch). Do exactly this: call ListAgents, find the session named \"$TARGET_NAME\", and send it ONE message with SendMessage, using the name exactly as the listing prints it (for example \"$TARGET_NAME [abc123]\"). The message text: \"Automated resume ping from your user (session-limit-watch): the usage limit has reset. Continue the task you were on when the limit stopped you, from where it left off, under the same constraints you had. If you were not interrupted and are already working or waiting on your user, ignore this.\" Then reply with exactly one line: DELIVERED, or FAILED: <reason>. Do nothing else."
out=$(cd "$HOME" && claude -p "$PROMPT" --permission-mode bypassPermissions --model "$MODEL" --no-session-persistence --max-turns 4 --output-format json 2>&1)
res=$(printf '%s' "$out" | python3 -I -c '
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw[raw.index("{"):]) if "{" in raw else {}
except Exception:
    d={}
print(json.dumps({"err":d.get("is_error"),"st":d.get("api_error_status"),"r":str(d.get("result",""))[:300],"raw":raw[:300] if not d else ""}))' 2>/dev/null)
if printf "%s" "$res" | /usr/bin/grep -q '"err": *false' && printf "%s" "$res" | /usr/bin/grep -q 'DELIVERED'; then
  echo ok > "$STATE"; log "reset: resume ping DELIVERED to '$TARGET_NAME'; state ok"
elif printf "%s" "$out" | /usr/bin/grep -qi -E "usage limit|hit your limit|rate.?limit|429"; then
  log "still limited: $(printf '%s' "$res" | cut -c1-200)"
else
  log "ping attempt did not confirm delivery; will retry: $(printf '%s' "$res" | cut -c1-300)"
fi

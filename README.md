# session-limit-watch

A Claude Code skill that keeps a long-running Claude Code session going across the
account's 5-hour usage-limit resets, without any Claude session being awake to do it.

When the limit stops a session, every other session on the account is stopped too, so
nothing inside Claude can wait for the reset. This skill moves the waiting out to
`launchd`: a small shell script runs every few minutes, notices the limit banner on the
target session's screen, and once the limit lifts it starts a fresh headless
`claude -p` session whose only job is to message the target: "the limit has reset,
continue what you were doing".

## Install

```sh
git clone https://github.com/iliasaz/session-limit-watch ~/.claude/skills/session-limit-watch
```

Then, inside any Claude Code session:

```
/session-limit-watch <session-name>              # install, check every 300 s
/session-limit-watch <session-name> install 120  # custom interval
/session-limit-watch <session-name> status
/session-limit-watch <session-name> test         # sends one real resume ping
/session-limit-watch <session-name> remove
```

`<session-name>` is the display name shown by `claude agents --json` (set it with
`claude -n <name>` or `/rename` inside the session).

The scripts also work without the skill wrapper:

```sh
bash scripts/install.sh <session-name> [interval-seconds]
bash scripts/status.sh <session-name>
bash scripts/test.sh <session-name>
bash scripts/uninstall.sh <session-name>
```

## How it works

1. `launchd` runs `scripts/limit-watch.sh <name>` every N seconds (default 300).
2. The script finds the session's process with `claude agents --json`. If the session runs
   inside [Supacode](https://supacode.app) it reads the last 40 lines of its terminal
   through Supacode's `zmx` multiplexer and looks for the limit banner. Seeing it writes
   `limited <epoch>` to a state file. This step makes no API call.
3. While the state is `limited`, each tick runs a fresh headless session on Haiku with a
   fixed prompt and `--max-turns 4`: list agents, send the resume message to `<name>`,
   reply `DELIVERED` or `FAILED`. While the limit still holds this fails for free. The first
   `DELIVERED` is the reset, and the state returns to `ok`.

One ping per reset. The target session decides whether it was actually interrupted.

The pinger uses `--permission-mode bypassPermissions` only because cross-session messages
are held for user approval unless sender and recipient share a permission class, and
long-running sessions usually run in bypass mode. Its prompt is fixed in the script.

## Files

- `SKILL.md` — the skill definition Claude Code loads
- `scripts/limit-watch.sh` — the watcher, run by launchd
- `scripts/install.sh`, `uninstall.sh`, `status.sh`, `test.sh`
- per target session:
  `~/Library/LaunchAgents/com.claude.session-limit-watch.<name>.plist` and
  `~/.local/state/session-limit-watch/<name>/{state,log,launchd.out,launchd.err}`
- `LIMIT_WATCH_MODEL` overrides the pinger's model (default Haiku 4.5)

## Limits

- macOS only: it depends on `launchd`, and banner detection depends on Supacode's `zmx`.
  For a target in another terminal the ping path still works; mark the state by hand:
  `echo "limited $(date +%s)" > ~/.local/state/session-limit-watch/<name>/state`
- The banner wording is matched as of Claude Code 2.1.296. If it changes, set the state
  by hand as above and update the pattern in `scripts/limit-watch.sh`.
- Each ping costs one short Haiku session (a few cents).

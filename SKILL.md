---
name: session-limit-watch
description: Install a launchd watcher that notices when a named Claude Code session was stopped by the 5-hour usage limit, waits for the reset, and prompts a fresh headless claude session to tell that session to continue. Use when the user asks to keep a long-running session going across usage-limit resets, or says "set up a limit watch for <session>".
argument-hint: <session-name> [install|status|test|remove] [interval-seconds]
---

# session-limit-watch

Keeps a long-running Claude Code session going across usage-limit resets without any
Claude session being awake to do it. Everything runs from `launchd`, so it works while
every session on the account is blocked by the limit.

## How it works (per target session)

1. Every N seconds (default 300) `scripts/limit-watch.sh <name>` finds the session named
   `<name>` with `claude agents --json`.
2. If the session runs inside Supacode (zmx), it reads the last 40 lines of its terminal
   for the limit banner (`Usage limit reached …` / `You've hit your limit`). Seeing it
   writes `limited <epoch>` to the state file. This step costs nothing.
3. While the state is `limited`, each tick runs a fresh headless session,
   `claude -p "<fixed prompt>"` on Haiku, whose only job is: ListAgents → SendMessage to
   `<name>`: "the usage limit has reset; continue the task you were on when the limit
   stopped you, from where it left off; ignore this if you were not interrupted". While the
   limit holds that session fails for free; the first `DELIVERED` is the reset, and the
   state returns to `ok`.

The pinger runs with `--permission-mode bypassPermissions` only because cross-session
messages are held for user approval unless sender and recipient share a permission class
and long-running sessions usually run in bypass. It has a fixed prompt and `--max-turns 4`.

## Commands

Parse `$ARGUMENTS` as `<session-name> [action] [interval]`; action defaults to `install`.
The session name is the display name shown by `claude agents --json` / ListAgents
(set with `claude -n <name>` or `/rename`).

- `install`: `bash ~/.claude/skills/session-limit-watch/scripts/install.sh <name> [interval]`
  then run `status`. Tell the user the plist label, state and log paths, and that the
  banner detection only works for sessions inside Supacode; for other terminals the
  limited state can be set by hand: `echo "limited $(date +%s)" > ~/.local/state/session-limit-watch/<name>/state`.
- `status`: `bash ~/.claude/skills/session-limit-watch/scripts/status.sh <name>`
- `test`: ask the user first — it sends one real resume ping to the target — then
  `bash ~/.claude/skills/session-limit-watch/scripts/test.sh <name>` and show the log tail.
  Afterwards, if you can, message the target that the ping was a test.
- `remove`: `bash ~/.claude/skills/session-limit-watch/scripts/uninstall.sh <name>`

## Files

- `~/Library/LaunchAgents/com.claude.session-limit-watch.<name>.plist`
- `~/.local/state/session-limit-watch/<name>/{state,log,launchd.out,launchd.err}`
- `LIMIT_WATCH_MODEL` env var overrides the pinger's model (default Haiku 4.5).

## Limits

- macOS only (launchd, Supacode's zmx). Banner detection needs the target to run inside
  Supacode; the ping path needs only `claude` on PATH and the target session alive.
- The banner wording is matched as of Claude Code 2.1.296; if it changes, set the state by hand.
- One ping per reset; the target decides whether it was interrupted.

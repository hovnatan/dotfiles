#!/usr/bin/env bash
# loaded-check.sh -- say so when the session-done mod it sits beside is not
# running in a claude session. A SessionStart hook of
# home/.claude/settings.json, so it runs whether or not any mod loads: that
# is the point.
#
# Why. The mod turns Claude Code's own idle bell off for good
# (engine-bell-off.sh, a key in ~/.claude.json that outlives it) and rings
# in its place. A claude in which the mod does not load -- the mods folder
# moved, a Claude Code whose mod API moved on, mods turned off -- then rings
# nothing at all and pushes nothing, and nothing says so: the one sign was a
# line missing from a log. A session started before the two mods were merged
# sat silent like that for hours (2026-11-20).
#
#   SessionStart (stdin: {"session_id": "4f1c9a2e-...", "cwd": "/home/u/work/bench", ...})
#     |
#     v   the mod's own SessionStart hook (hooks/register.ts), where it runs:
#     |     SESSION_DONE_MOD_SESSION=4f1c9a2e-... in claude's environment,
#     |     for as long as the hooks beneath it take
#     v
#   this hook: is $SESSION_DONE_MOD_SESSION this session's id?
#     |-- yes --> "check: mod running", exit 0
#     '-- no ---> a warning on the person's screen (systemMessage),
#                 "check: FAILED, ..." in the log, exit 0
#
# The mark is the mod's word that it is running, given in order: Claude Code
# runs a mod's hooks above the settings' own, so the mod has set it by the
# time this one starts, and there is nothing to wait for (seen live on
# 2.1.329 at a startup, a resume, a /clear and a compaction). It names the
# session because an environment is inherited: a claude started from inside
# another's SessionStart would find that one's mark, and not its own id.
#
# The warning says which of two states the session is in, by the key in
# ~/.claude.json: the engine's bell off (no bell at all) or still on (its
# bell a minute after every turn end; no push). It restores nothing: the key
# is every running claude's, and turning the engine's bell back on would
# ring twice in each session where the mod does run.
#
# One line a SessionStart in the mod's own log, beside the mod's:
#   ~/.dotfiles/.logs/<UTC day>_claude_session_done/events.log
#   2026-11-20T04:28:13Z bench 4f1c9a2e check: mod running
#   2026-11-20T04:31:02Z bench 9d02c1aa check: FAILED, the mod is not running; Claude Code's own idle bell is off: no bell, no push
#
# Needs jq (nix/flake.nix), as engine-bell-off.sh does. Exit 1 and the
# reason on stderr for what it cannot judge: no session id on stdin, no
# ~/.claude.json, a log that cannot be written.
set -euo pipefail

MOD=${0%/*}
# shellcheck source=scripts/lib/event_log.sh
. "$MOD/../../../../scripts/lib/event_log.sh"

die() {
  echo "loaded-check.sh: $*" >&2
  exit 1
}

# The session, as the mod names it in the log: its folder and the start of
# its id, "bench 4f1c9a2e". read fails at the input's end, having read it.
IFS= read -r -d '' input || true
fields=$(jq -r '.session_id // "", .cwd // ""' <<<"$input") || die "the SessionStart input is not JSON: $input"
{
  IFS= read -r id
  IFS= read -r cwd
} <<<"$fields" || true
[ -n "$id" ] && [ -n "${cwd:-}" ] || die "no session_id or cwd in the SessionStart input: $input"
who="${cwd##*/} ${id:0:8}"

if [ "${SESSION_DONE_MOD_SESSION:-}" = "$id" ]; then
  event_log_note claude_session_done "$who" "check: mod running" || die "cannot log under $EVENT_LOG_ROOT"
  exit 0
fi

# An assignment, so its failure is this hook's: its own stderr names what it
# cannot read.
bell=$("$MOD/engine-bell-off.sh" --state)
case $bell in
  off) state="Claude Code's own idle bell is off: no bell, no push" ;;
  on) state="Claude Code's own idle bell rings in its place (a minute after every turn end), and there is no push" ;;
  *) die "engine-bell-off.sh --state said \"$bell\", neither on nor off" ;;
esac
event_log_note claude_session_done "$who" "check: FAILED, the mod is not running; $state" \
  || die "cannot log under $EVENT_LOG_ROOT"

# systemMessage is the hook output Claude Code shows the person.
mod=$(cd "$MOD" && pwd)
jq -cn --arg text "session-done: the mod is not running in this session. $state. Why: claude plugin validate $mod, and CLAUDE_CODE_PLUGIN_DIRS in ~/.claude/settings.json. $mod/engine-bell-off.sh has how to turn Claude Code's own bell back on." \
  '{ systemMessage: $text }'

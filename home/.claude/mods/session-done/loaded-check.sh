#!/usr/bin/env bash
# loaded-check.sh -- say so when the session-done mod it sits beside is not
# running in a claude session. A SessionStart hook of
# home/.claude/settings.json, so it runs whether or not any mod loads: that
# is the point.
#
# Why. A claude in which the mod does not load -- the mods folder moved, a
# Claude Code whose mod API moved on, mods turned off -- pushes nothing to
# the phone, and nothing says so: the one sign is a line missing from a log.
# A session started before this mod took the push over from the one that
# had it (ntfy-stop) sat like that for hours (2026-11-20).
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
# One line a SessionStart in the mod's own log, beside the mod's:
#   ~/.dotfiles/.logs/<UTC day>_claude_session_done/events.log
#   2026-11-20T04:28:13Z bench 4f1c9a2e check: mod running
#   2026-11-20T04:31:02Z bench 9d02c1aa check: FAILED, the mod is not running: no push
#
# Needs jq (nix/flake.nix). Exit 1 and the reason on stderr for what it
# cannot judge: no session id on stdin, a log that cannot be written.
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

event_log_note claude_session_done "$who" "check: FAILED, the mod is not running: no push" \
  || die "cannot log under $EVENT_LOG_ROOT"

# systemMessage is the hook output Claude Code shows the person.
mod=$(cd "$MOD" && pwd)
jq -cn --arg text "session-done: the mod is not running in this session, so nothing is pushed to the phone when it waits unwatched. Why: claude plugin validate $mod, and CLAUDE_CODE_PLUGIN_DIRS in ~/.claude/settings.json." \
  '{ systemMessage: $text }'

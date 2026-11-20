#!/usr/bin/env bash
# loaded-check.sh -- say so when the session-done mod it sits beside did not
# start in a claude session. A SessionStart hook of home/.claude/settings.json,
# so it runs whether or not any mod loads: that is the point.
#
# Why. The mod turns Claude Code's own idle bell off for good
# (engine-bell-off.sh, a key in ~/.claude.json that outlives it) and rings
# in its place. A claude in which the mod does not load -- the mods folder
# moved, a Claude Code whose mod API moved on, mods turned off -- then rings
# nothing at all and pushes nothing, and nothing says so: the one sign was a
# line missing from a log. A session started before the two mods were merged
# sat silent like that for hours (2026-11-20).
#
#   SessionStart, startup | resume
#   (stdin: {"session_id": "4f1c9a2e-...", "cwd": "/home/u/work/bench", ...})
#     |
#     v
#   the mod's line for this session and this start in today's log?
#     "2026-11-20T04:28:13Z bench 4f1c9a2e session: started, ..."
#     |-- there, or within WAIT seconds --> "check: mod started", exit 0
#     '-- not there -----> a warning on the person's screen (systemMessage),
#                          "check: FAILED, ..." in the log, exit 0
#
# The mod's line is its `session: ...` one, written at its session.start,
# whatever it says after that (started | FAILED to turn the engine's bell
# off: either way the mod is running). The mod's start and this hook are not
# ordered, hence the wait, and a line counts from SLACK seconds before this
# hook began: a resumed session keeps its id, and the line of its last start
# is not this start's.
#
# For the `startup` and `resume` sources alone (the hook's matcher): a
# /clear or a compaction raises SessionStart again, in the same claude, but
# not the mod's session.start, and the mod that started with the process is
# still there (seen live on 2.1.329: a /clear gave the session a new id and
# no line).
#
# The warning says which of two states the session is in, by the key in
# ~/.claude.json: the engine's bell off (no bell at all) or still on (its
# bell a minute after every turn end; no push). It restores nothing: the key
# is every running claude's, and turning the engine's bell back on would
# ring twice in each session where the mod does run.
#
# One line a start in the mod's own log, beside the mod's:
#   ~/.dotfiles/.logs/<UTC day>_claude_session_done/events.log
#   2026-11-20T04:28:13Z bench 4f1c9a2e check: mod started
#   2026-11-20T04:31:02Z bench 9d02c1aa check: FAILED, the mod did not start within 5s; Claude Code's own idle bell is off: no bell, no push
#
# Needs jq (nix/flake.nix), as engine-bell-off.sh does. Exit 1 and the
# reason on stderr for what it cannot judge: no session id on stdin, no
# ~/.claude.json, a log that cannot be written.
set -euo pipefail

WAIT=${SESSION_DONE_CHECK_WAIT_SECONDS:-5}
SLACK=30
MOD=$(cd "${0%/*}" && pwd)
# shellcheck source=scripts/lib/event_log.sh
. "$MOD/../../../../scripts/lib/event_log.sh"

die() {
  echo "loaded-check.sh: $*" >&2
  exit 1
}

# The session, as the mod names it in the log: its folder and the start of
# its id, "bench 4f1c9a2e".
input=$(cat)
id=$(jq -r '.session_id // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
[ -n "$id" ] && [ -n "$cwd" ] || die "no session_id or cwd in the SessionStart input: $input"
who="${cwd##*/} ${id:0:8}"

# Lines no older than this are this start's. jq does the arithmetic: date's
# flags for it differ between macOS and Linux.
since=$(jq -rn --argjson slack "$SLACK" 'now - $slack | todate')

# started: whether the mod's line is in the log. The two newest day logs
# are read: a start at 00:00:01 may have its line in yesterday's.
started() {
  set -- "$EVENT_LOG_ROOT"/*_claude_session_done/events.log
  [ -f "$1" ] || return 1 # no log yet: the pattern stayed as typed
  [ $# -le 2 ] || shift $(($# - 2))
  awk -v since="$since" -v key=" ${id:0:8} session: " \
    '$1 >= since && index($0, key) { found = 1 } END { exit !found }' "$@"
}

# Asked five times a second: the mod's start is a few milliseconds' work, and
# only a mod that is not coming is waited out in full.
tries=$((WAIT * 5))
while ! started; do
  if [ "$tries" -le 0 ]; then
    file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
    [ -f "$file" ] || die "no $file, where Claude Code keeps messageIdleNotifThresholdMs"
    if [ "$(jq -r '.messageIdleNotifThresholdMs // "unset"' "$file")" = 2147483647 ]; then
      state="Claude Code's own idle bell is off: no bell, no push"
    else
      state="Claude Code's own idle bell rings in its place (a minute after every turn end), and there is no push"
    fi
    event_log_note claude_session_done "$who" "check: FAILED, the mod did not start within ${WAIT}s; $state" \
      || die "cannot log under $EVENT_LOG_ROOT"

    # systemMessage is the hook output Claude Code shows the person.
    jq -cn --arg text "session-done: the mod did not start in this session. $state. Why: claude plugin validate $MOD, and CLAUDE_CODE_PLUGIN_DIRS in ~/.claude/settings.json. $MOD/engine-bell-off.sh has how to turn Claude Code's own bell back on." \
      '{ systemMessage: $text }'
    exit 0
  fi
  tries=$((tries - 1))
  sleep 0.2
done

event_log_note claude_session_done "$who" "check: mod started" || die "cannot log under $EVENT_LOG_ROOT"

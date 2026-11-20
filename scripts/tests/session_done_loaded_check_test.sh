#!/usr/bin/env bash
# check.sh covers: home/.claude/mods/session-done/loaded-check.sh scripts/lib/event_log.sh
#
# session_done_loaded_check_test.sh --
# home/.claude/mods/session-done/loaded-check.sh, the SessionStart hook that
# says so when the session-done mod did not start in a claude session. Runs
# it as Claude Code does, the hook's input on stdin, in throwaway homes: each
# has its own event log, where the mod's line is written or not, and its own
# ~/.claude.json. Whether Claude Code shows the warning was seen live
# (2.1.329, 2026-11-20: "SessionStart:startup says: ..."). Needs jq; about
# 5 s, the waits for a line that does not come.
#
#   the log holds, for session 4f1c9a2e     -> stdout, exit, the line logged
#   the mod's "session: started", fresh     -> nothing, 0, "check: mod started"
#   the mod's "session: FAILED, ..."        -> the same: the mod is running
#   that line 0.5 s into the wait           -> the same
#   that line in the older of two day logs  -> the same (a start at midnight)
#   no line, the engine's bell off          -> a systemMessage: "no bell, no
#                                              push"; 0; "check: FAILED, ..."
#   no line, the engine's bell on           -> a systemMessage: its bell
#                                              "rings in its place"
#   no log at all                           -> a systemMessage
#   another session's line alone            -> a systemMessage
#   this session's line, 10 minutes old     -> a systemMessage (a resumed
#                                              session keeps its id)
#   no line, and no ~/.claude.json          -> exit 1, the file named
#   an input with no session_id             -> exit 1, the input named
#
# Exit 0 = all passed.

set -uo pipefail

command -v jq >/dev/null || {
  echo "session_done_loaded_check_test.sh: jq not on PATH" >&2
  exit 1
}

REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"
event_log_start session_done_loaded_check_test --no-prune

CHECK="$REPO/home/.claude/mods/session-done/loaded-check.sh"
NOTE="$REPO/scripts/event_log_note.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0
# log prints each line as well as recording it (scripts/lib/event_log.sh).
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}

INPUT='{"session_id":"4f1c9a2e-0000-4000-8000-000000000000","cwd":"/home/u/work/bench","hook_event_name":"SessionStart","source":"startup"}'
WHO='bench 4f1c9a2e'
STARTED="session: started, Claude Code's own idle bell is off"
OFF='{"messageIdleNotifThresholdMs":2147483647,"numStartups":7}'

# home <name> [<~/.claude.json's content>]: a throwaway home with an empty
# log root, and that state file unless none is given; prints the home.
home() {
  mkdir -p "$WORK/$1/.dotfiles/.logs"
  [ $# -lt 2 ] || printf '%s\n' "$2" >"$WORK/$1/.claude.json"
  echo "$WORK/$1"
}
# wrote <home> <who> <event>: a line in that home's log, as the mod writes it.
wrote() { HOME=$1 "$NOTE" claude_session_done "$2" "$3"; }
# logged <home>: every line of that home's logs, less the time stamps.
logged() { cat "$1"/.dotfiles/.logs/*_claude_session_done/events.log 2>/dev/null | cut -d' ' -f2-; }

# is <label> <home> <want status> <want stdout and stderr, an extended regex>
#    <want the home's log to end with> [<input>]: the hook run in that home,
#    with a wait of 1 s for the mod's line.
is() {
  local label=$1 h=$2 want=$3 re=$4 last=$5 out rc
  out=$(HOME=$h CLAUDE_CONFIG_DIR='' SESSION_DONE_CHECK_WAIT_SECONDS=1 "$CHECK" 2>&1 <<<"${6:-$INPUT}")
  rc=$?
  if [ "$rc" = "$want" ] && [[ "$out" =~ $re ]] && [ "$(logged "$h" | tail -1)" = "$last" ]; then
    pass "$label: exit $rc${out:+, \"${out:0:90}\"}"
  else
    fail "$label: exit $rc (want $want), output \"$out\" (want /$re/), the log ends \"$(logged "$h" | tail -1)\" (want \"$last\")"
  fi
}
OK="$WHO check: mod started"
SAID='^\{"systemMessage":"session-done: the mod did not start in this session\. '
NO_BELL="Claude Code's own idle bell is off: no bell, no push"
ITS_BELL="Claude Code's own idle bell rings in its place \(a minute after every turn end\), and there is no push"

# --- the mod started ---------------------------------------------------------

h=$(home started "$OFF")
wrote "$h" "$WHO" "$STARTED"
is "the mod's line is there" "$h" 0 '^$' "$OK"

# The mod could not turn the engine's bell off and said so: it is running.
h=$(home complained "$OFF")
wrote "$h" "$WHO" "session: FAILED, Claude Code's own idle bell could not be turned off, so it rings beside this one: jq: error"
is "the mod's line is a FAILED of its own" "$h" 0 '^$' "$OK"

# The hook and the mod's start are not ordered: the line may come second.
h=$(home late "$OFF")
(
  sleep 0.5
  wrote "$h" "$WHO" "$STARTED"
) &
is "the mod's line comes during the wait" "$h" 0 '^$' "$OK"
wait

# A start at midnight: the mod's line went to yesterday's log, and today's
# was begun by another session. The two newest logs are read.
h=$(home midnight "$OFF")
wrote "$h" "$WHO" "$STARTED"
mv "$h"/.dotfiles/.logs/*_claude_session_done "$h/.dotfiles/.logs/20000101_235959_claude_session_done"
mkdir "$h/.dotfiles/.logs/20000102_000001_claude_session_done"
echo "2000-01-02T00:00:01Z other 00000000 stop: done, bell rung via terminal_bell" \
  >"$h/.dotfiles/.logs/20000102_000001_claude_session_done/events.log"
is "the mod's line is in the older of two logs" "$h" 0 '^$' "$OK"

# --- the mod did not start ---------------------------------------------------

h=$(home silent "$OFF")
wrote "$h" 'other 00000000' "$STARTED"
is "another session's line alone, the engine's bell off" "$h" 0 "$SAID$NO_BELL\. " \
  "$WHO check: FAILED, the mod did not start within 1s; $NO_BELL"

h=$(home ringing '{"messageIdleNotifThresholdMs":60000}')
is "no log at all, the engine's bell at 60000" "$h" 0 "$SAID$ITS_BELL\. " \
  "$WHO check: FAILED, the mod did not start within 1s; Claude Code's own idle bell rings in its place (a minute after every turn end), and there is no push"

h=$(home unset '{"numStartups":7}')
is "no line, the engine's bell unset" "$h" 0 "$SAID$ITS_BELL\. " \
  "$WHO check: FAILED, the mod did not start within 1s; Claude Code's own idle bell rings in its place (a minute after every turn end), and there is no push"

# A resumed session keeps its id: the line of its last start is not this one's.
h=$(home resumed "$OFF")
wrote "$h" 'other 00000000' "$STARTED"
old=$(jq -rn 'now - 600 | todate')
echo "$old $WHO $STARTED" >>"$(echo "$h"/.dotfiles/.logs/*_claude_session_done/events.log)"
is "this session's line, 10 minutes old" "$h" 0 "$SAID$NO_BELL\. " \
  "$WHO check: FAILED, the mod did not start within 1s; $NO_BELL"

# --- what it cannot judge ----------------------------------------------------

h=$(home nostate)
is "no line and no ~/.claude.json" "$h" 1 "^loaded-check.sh: no $h/.claude.json, where Claude Code keeps " ''

h=$(home noid "$OFF")
is "an input with no session_id" "$h" 1 '^loaded-check.sh: no session_id or cwd in the SessionStart input: \{"cwd":"/x"\}$' '' '{"cwd":"/x"}'

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

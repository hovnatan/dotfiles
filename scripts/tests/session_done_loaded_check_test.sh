#!/usr/bin/env bash
#
# session_done_loaded_check_test.sh --
# home/.claude/mods/session-done/loaded-check.sh, the SessionStart hook that
# says so when the session-done mod is not running in a claude session. Runs
# it as Claude Code does, the hook's input on stdin and the mod's mark in
# the environment or not, in throwaway homes, each with its own event log.
# That the mod's mark reaches the hook, and that
# Claude Code shows the warning, was seen live (2.1.329, 2026-11-20:
# "SessionStart:startup says: ..."); hooks/register.test.ts has the mod's
# half. Needs jq; under a second.
#
#   $SESSION_DONE_MOD_SESSION, for session 4f1c9a2e-...
#                                           -> stdout, exit, the line logged
#   this session's id                       -> nothing, 0, "check: mod running"
#   unset                                   -> a systemMessage: nothing is
#                                              pushed; 0; "check: FAILED, ..."
#   another session's id                    -> the same (a claude started
#                                              inside another's start)
#   an input with no session_id, or not JSON -> exit 1, the input named
#
# Exit 0 = all passed.

set -uo pipefail

command -v jq >/dev/null || {
  echo "session_done_loaded_check_test.sh: jq not on PATH" >&2
  exit 1
}

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
. "$REPO/scripts/lib/event_log.sh"
event_log_start session_done_loaded_check_test --no-prune

CHECK="$REPO/home/.claude/mods/session-done/loaded-check.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ID=4f1c9a2e-0000-4000-8000-000000000000
INPUT="{\"session_id\":\"$ID\",\"cwd\":\"/home/u/work/bench\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
WHO='bench 4f1c9a2e'

# home <name>: a throwaway home with an empty log root; prints the home.
home() {
  mkdir -p "$WORK/$1/.dotfiles/.logs"
  echo "$WORK/$1"
}
# logged <home>: every line of that home's logs, less the time stamps.
logged() { cat "$1"/.dotfiles/.logs/*_claude_session_done/events.log 2>/dev/null | cut -d' ' -f2-; }

# is <label> <home> <the mark, "" for none> <want status>
#    <want stdout and stderr, an extended regex> <want the home's log to end
#    with> [<input>]: the hook run in that home.
is() {
  local label=$1 h=$2 mark=$3 want=$4 re=$5 last=$6 out rc
  out=$(
    [ -z "$mark" ] || export SESSION_DONE_MOD_SESSION=$mark
    HOME=$h "$CHECK" 2>&1 <<<"${7:-$INPUT}"
  )
  rc=$?
  if [ "$rc" = "$want" ] && [[ "$out" =~ $re ]] && [ "$(logged "$h" | tail -1)" = "$last" ]; then
    pass "$label: exit $rc${out:+, \"${out:0:90}\"}"
  else
    fail "$label: exit $rc (want $want), output \"$out\" (want /$re/), the log ends \"$(logged "$h" | tail -1)\" (want \"$last\")"
  fi
}
# warns <label> <home> <the mark>: the hook says so on screen and in the
# log, and exits 0.
warns() {
  is "$1" "$2" "$3" 0 '^\{"systemMessage":"session-done: the mod is not running in this session, so nothing is pushed to the phone when it waits unwatched\. Why: claude plugin validate [^ ]+/session-done, and CLAUDE_CODE_PLUGIN_DIRS in ~/\.claude/settings\.json\."\}$' \
    "$WHO check: FAILED, the mod is not running: no push"
}

# --- the mod is running ------------------------------------------------------

unset SESSION_DONE_MOD_SESSION # this test may itself run under a claude's start
is "the mod's mark names this session" "$(home running)" "$ID" 0 '^$' "$WHO check: mod running"

# --- the mod is not ----------------------------------------------------------

warns "no mark" "$(home unmarked)" ''
# An environment is inherited: the mark of the claude this one was started
# from is not this session's.
warns "the mark names another session" "$(home inherited)" 00000000-0000-4000-8000-000000000000

# --- what it cannot judge ----------------------------------------------------

h=$(home noid)
is "an input with no session_id" "$h" '' 1 '^loaded-check.sh: no session_id or cwd in the SessionStart input: \{"cwd":"/x"\}$' '' '{"cwd":"/x"}'
is "an input that is not JSON" "$h" '' 1 'loaded-check.sh: the SessionStart input is not JSON: nonsense$' '' 'nonsense'

finish

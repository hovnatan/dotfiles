#!/usr/bin/env bash
# check.sh covers: home/.claude/session-name-prefix.sh scripts/machine_name.sh scripts/lib/event_log.sh
#
# session_name_prefix_test.sh -- home/.claude/session-name-prefix.sh fed
# UserPromptSubmit payloads the way Claude Code sends them, under a throwaway
# HOME whose machine is "mbp":
#
#   payload {"session_title":<name>,...} -> hook -> sessionTitle | nothing
#
#   no session_title, null, ""        -> nothing   (the session has no name)
#   "fix-flaky-login"                 -> mbp/fix-flaky-login, and a log line
#   "mbp/dotfiles"                    -> nothing   (already this machine's)
#   "mbpx/foo", "mbp"                 -> mbp/mbpx/foo, mbp/mbp  (the prefix
#                                        is the whole word and its slash)
#   a name with quotes, a backslash   -> the same name back, as valid JSON
#   a prompt that says "session_title":"mbp/x", session with no name -> nothing
#   a machine-name file of two words  -> exit 1, the file named, no answer
#   no jq on PATH                     -> exit 1, jq named, no answer; but
#                                        "mbp/dotfiles" -> nothing, jq unasked
#
# Needs jq; about 1 s. Usage: scripts/tests/session_name_prefix_test.sh
# (exit 0 = all passed)
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"
event_log_start session_name_prefix_test --no-prune

command -v jq >/dev/null || {
  log "FAIL jq is not on PATH; this test builds its payloads with it"
  exit 1
}

HOOK="$REPO/home/.claude/session-name-prefix.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"
FILE="$H/.config/dotfiles/machine-name"
mkdir -p "${FILE%/*}"
echo mbp >"$FILE"

failures=0
# log prints each line as well as recording it (scripts/lib/event_log.sh).
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}

# The hook's own log lands under the throwaway HOME, one file for the day.
hook_log() { cat "$H"/.dotfiles/.logs/*_claude_session_name/events.log 2>/dev/null; }

# answer <payload> [PATH]: the hook's stdout; its stderr goes to $WORK/err.
answer() { HOME="$H" PATH="${2:-$PATH}" "$HOOK" <<<"$1" 2>"$WORK/err"; }

# payload <session_title as JSON, or '"absent"'> [prompt]: a UserPromptSubmit
# payload with the fields Claude Code 2.1.328 sends.
payload() {
  jq -cn --argjson t "$1" --arg p "${2:-hi}" '{session_id: "s-1",
    transcript_path: "/x/s-1.jsonl", cwd: "/x",
    hook_event_name: "UserPromptSubmit", prompt: $p}
    + (if $t == "absent" then {} else {session_title: $t} end)'
}

expect_silent() { # <what> <payload>
  local got rc
  got=$(answer "$2")
  rc=$?
  [ "$rc" = 0 ] && [ -z "$got" ] && pass "$1 -> nothing" \
    || fail "$1: wanted nothing and exit 0, got exit $rc, '$got', stderr '$(<"$WORK/err")'"
}

expect_title() { # <what> <payload> <wanted name>
  local got rc
  got=$(answer "$2")
  rc=$?
  [ "$rc" = 0 ] && jq -e --arg t "$3" '.hookSpecificOutput
      | .sessionTitle == $t and .hookEventName == "UserPromptSubmit"' <<<"$got" >/dev/null 2>&1 \
    && pass "$1 -> $3" \
    || fail "$1: wanted '$3', got exit $rc, '$got', stderr '$(<"$WORK/err")'"
}

expect_refused() { # <what> <payload> <text stderr must hold> [PATH]
  local got rc
  got=$(answer "$2" "${4:-$PATH}")
  rc=$?
  [ "$rc" = 1 ] && [ -z "$got" ] && [[ "$(<"$WORK/err")" == *"$3"* ]] \
    && pass "$1 is refused, and says why" \
    || fail "$1: wanted exit 1 naming '$3', got exit $rc, '$got', stderr '$(<"$WORK/err")'"
}

# --- a session with no name is left alone, and nothing is logged -----------
expect_silent "no session_title" "$(payload '"absent"')"
expect_silent "session_title null" "$(payload null)"
expect_silent "session_title empty" "$(payload '""')"
expect_silent "a prompt saying \"session_title\", no name" \
  "$(payload '"absent"' 'what is "session_title":"mbp/x"?')"
[ -z "$(hook_log)" ] && pass "nothing logged for sessions with no name" \
  || fail "sessions with no name were logged: $(hook_log)"

# --- a name without the machine gets it -------------------------------------
expect_title "a generated name" "$(payload '"fix-flaky-login"')" mbp/fix-flaky-login
want="s-1: 'fix-flaky-login' -> 'mbp/fix-flaky-login'"
[[ "$(hook_log)" == *"$want" ]] && pass "the rename is logged: $want" \
  || fail "the hook's log lacks \"$want\": '$(hook_log)'"
expect_title "another word that starts with the machine's" "$(payload '"mbpx/foo"')" mbp/mbpx/foo
expect_title "the machine's name alone" "$(payload '"mbp"')" mbp/mbp
odd='say "hi" \ there'
expect_title "a name with quotes and a backslash" "$(payload "$(jq -cn --arg t "$odd" '$t')")" "mbp/$odd"

# --- a name that has it is left alone ---------------------------------------
lines=$(hook_log | wc -l)
expect_silent "a name with the machine in front" "$(payload '"mbp/dotfiles"')"
[ "$(hook_log | wc -l)" = "$lines" ] && pass "nothing logged for a name left alone" \
  || fail "a name left alone was logged: $(hook_log | tail -1)"

# --- failures say why and answer nothing ------------------------------------
echo "two words" >"$FILE"
expect_refused "a machine-name file of two words" "$(payload '"x"')" "$FILE"
echo mbp >"$FILE"

# A PATH with bash alone: all the hook runs until a name needs reading. The
# payloads are built first, with this shell's jq.
nojq="$WORK/nojq"
mkdir "$nojq"
ln -s "$(command -v bash)" "$nojq/bash"
bare=$(payload '"x"') prefixed=$(payload '"mbp/dotfiles"')
expect_refused "no jq on PATH" "$bare" "jq is not on PATH" "$nojq"
n=$(answer "$prefixed" "$nojq")
rc=$?
[ "$rc" = 0 ] && [ -z "$n" ] && pass "a name with the machine in front needs no jq" \
  || fail "a name with the machine in front, no jq: exit $rc, '$n', stderr '$(<"$WORK/err")'"

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

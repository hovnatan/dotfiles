#!/usr/bin/env bash
# session-name-prefix.sh -- UserPromptSubmit hook: a claude session whose
# name lacks this machine's name in front gets it, so a name claude made up
# (an empty /rename) reads like one given at launch (`claude -n mbp/x`).
#
#   /rename                 claude names the session   "fix-flaky-login"
#   next prompt             claude -> hook  {"session_title":"fix-flaky-login",...}
#                           hook -> claude  {"hookSpecificOutput":{
#                                             "sessionTitle":"mbp/fix-flaky-login"}}
#   prompts after that      session_title is "mbp/fix-flaky-login": nothing to do
#
# Why at the next prompt and not at the /rename: /rename makes the name and
# applies it in one step and fires no hook (Claude Code 2.1.328, checked by
# logging UserPromptSubmit, UserPromptExpansion and SessionStart around
# one). UserPromptSubmit is the first event after it that is both told the
# session's name (session_title) and may answer with another
# (sessionTitle). Until that prompt the name shows without the machine.
#
# What it does not tell apart: a name claude generated and one typed
# (`/rename foo`, `claude -n foo`). The payload carries the name, not where
# it came from, so both become <machine>/<name>. A session with no name
# (only claude's own summary title) sends no session_title and is left
# alone.
#
# The machine's name is scripts/machine_name.sh's. Each rename is a line in
# ~/.dotfiles/.logs/<day>_claude_session_name/events.log.
#
# A failure (no jq, a machine name that cannot be read) exits non-zero with
# the reason on stderr: Claude Code shows it as a hook error and the prompt
# still goes through, unrenamed.
set -euo pipefail

# Runs at every prompt, so the two common cases leave without starting a
# program (measured 2026-11-19 on a Mac, where bash alone takes 4 ms):
#
#   no name                      builtins only                     ~5 ms
#   a name with the machine      + machine_name.sh in a subshell   ~6 ms
#   a name without it (rare)     + jq, the log, the answer
payload=''
IFS= read -r -d '' payload || true
[[ $payload == *'"session_title"'* ]] || exit 0

# By expansion, not dirname, which would be a fork and a program (as
# ntfy-stop.sh finds itself).
case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac

# Sourced in the subshell rather than run: the same script and the same
# checks without a second bash (4.5 ms). Its `exit 1` ends the subshell, and
# `set -e` then ends this hook with its message on stderr.
machine=$(
  # shellcheck source=scripts/machine_name.sh
  . "$here/../../scripts/machine_name.sh"
)

# The name as claude writes it, compact, is enough to see the machine is
# there. The match cannot come from inside a string (a prompt quoting it):
# there every quote is \" and this needs two bare ones around the colon.
# Anything else (spaced JSON, an escaped name) goes on to jq.
[[ $payload == *'"session_title":"'"$machine"/* ]] && exit 0

command -v jq >/dev/null || {
  echo "session-name-prefix.sh: jq is not on PATH, so the session's name cannot be read; install it (nix/flake.nix)" >&2
  exit 1
}

# `// ""`: the key can be there and null. An empty name is no name.
title=$(jq -r '.session_title // ""' <<<"$payload")
[ -n "$title" ] || exit 0
[[ $title == "$machine"/* ]] && exit 0

# shellcheck source=scripts/lib/event_log.sh
. "$here/../../scripts/lib/event_log.sh"

new="$machine/$title"
event_log_note claude_session_name \
  "$(jq -r '.session_id // "?"' <<<"$payload"): '$title' -> '$new'"

# jq writes the answer: a name can hold quotes and backslashes.
jq -cn --arg t "$new" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", sessionTitle: $t}}'

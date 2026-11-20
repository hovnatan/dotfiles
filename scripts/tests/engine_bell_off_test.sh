#!/usr/bin/env bash
# check.sh covers: home/.claude/mods/session-done/engine-bell-off.sh
#
# engine_bell_off_test.sh -- home/.claude/mods/session-done/engine-bell-off.sh,
# the script the session-done mod runs to turn Claude Code's own idle bell off
# in claude's state file. Runs it on throwaway copies of such a file, named
# through CLAUDE_CONFIG_DIR as claude itself is told where it lives. What the
# mod does with the script's answer is hooks/register.test.ts's
# (scripts/tests/claude_mods_test.sh runs it). Needs jq; under a second.
#
#   the key unset        -> set to 2147483647, "was unset", the other keys
#                           and the file's mode kept, no temp file left
#   the key at 60000     -> set, "was 60000"
#   off already          -> nothing printed, the file not rewritten
#   $HOME's file         -> used when CLAUDE_CONFIG_DIR names none
#   --state              -> "on" for the key unset or at 60000, "off" for it
#                           off, and the file as it was either way
#   no file              -> exit 1, the path named
#   a file that is not JSON -> exit non-zero, the file as it was
#
# Exit 0 = all passed.

set -uo pipefail

command -v jq >/dev/null || {
  echo "engine_bell_off_test.sh: jq not on PATH" >&2
  exit 1
}

REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"
event_log_start engine_bell_off_test --no-prune

OFF_SH="$REPO/home/.claude/mods/session-done/engine-bell-off.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0
# log prints each line as well as recording it (scripts/lib/event_log.sh).
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}

# config <name> <json>: a config directory holding that state file, readable
# by its owner alone as claude's is; prints the directory.
config() {
  mkdir "$WORK/$1"
  printf '%s\n' "$2" >"$WORK/$1/.claude.json"
  chmod 600 "$WORK/$1/.claude.json"
  echo "$WORK/$1"
}

# is <label> <want status> <want output, an extended regex> <config dir>
#    [<engine-bell-off.sh's argument>]
is() {
  local label=$1 want=$2 re=$3 out rc
  out=$(CLAUDE_CONFIG_DIR="$4" "$OFF_SH" ${5:+"$5"} 2>&1)
  rc=$?
  if [ "$rc" = "$want" ] && [[ "$out" =~ $re ]]; then
    pass "$label: exit $rc${out:+, \"$out\"}"
  else
    fail "$label: exit $rc (want $want), output \"$out\" (want /$re/)"
  fi
}

# holds <label> <config dir> <jq filter that must be true of the file>
holds() {
  if jq -e "$3" "$2/.claude.json" >/dev/null; then
    pass "$1"
  else
    fail "$1: not true of $(cat "$2/.claude.json"): $3"
  fi
}

# beside <config dir>: what the directory holds besides the state file, one
# path a line; nothing when the script left no temp file.
beside() { find "$1" -mindepth 1 ! -name .claude.json; }

OFF='.messageIdleNotifThresholdMs == 2147483647'

# --- the key unset ------------------------------------------------------------

# An id beyond 2^53 stands for what the rewrite must not round.
dir=$(config unset '{"numStartups": 41, "userID": 12345678901234567890, "projects": {"/home/u": {"hasTrust": true}}}')
is "the key unset" 0 '^was unset$' "$dir"
holds "the key unset: now off" "$dir" "$OFF"
holds "the key unset: the other keys kept" "$dir" '.numStartups == 41 and .projects["/home/u"].hasTrust == true'
if grep -q '"userID": 12345678901234567890' "$dir/.claude.json"; then
  pass "the key unset: a number beyond 2^53 kept as written"
else
  fail "the key unset: a number beyond 2^53 changed: $(grep userID "$dir/.claude.json")"
fi
# find's -perm, as stat's flags differ between macOS and Linux.
if [ -n "$(find "$dir/.claude.json" -perm 600)" ]; then
  pass "the key unset: the file still its owner's alone"
else
  fail "the key unset: the file's mode is no longer 600"
fi
if [ -z "$(beside "$dir")" ]; then
  pass "the key unset: no temp file left"
else
  fail "the key unset: left in the directory: $(beside "$dir")"
fi

# --- the key at the engine's default -------------------------------------------

dir=$(config default '{"messageIdleNotifThresholdMs": 60000}')
is "the key at 60000" 0 '^was 60000$' "$dir"
holds "the key at 60000: now off" "$dir" "$OFF"

# --- off already: the file is left alone ----------------------------------------

# A second name for the file as it stands: a rewrite renames a new file over
# the first name, and the two then name different files.
dir=$(config off '{"messageIdleNotifThresholdMs": 2147483647, "numStartups": 41}')
ln "$dir/.claude.json" "$WORK/off.before"
is "off already" 0 '^$' "$dir"
if [ "$dir/.claude.json" -ef "$WORK/off.before" ]; then
  pass "off already: the file not rewritten"
else
  fail "off already: the file was rewritten"
fi

# --- no CLAUDE_CONFIG_DIR: the file is $HOME's ----------------------------------

dir=$(config home '{}')
out=$(env -u CLAUDE_CONFIG_DIR HOME="$dir" "$OFF_SH" 2>&1)
rc=$?
if [ "$rc" = 0 ] && [ "$out" = "was unset" ]; then
  pass "no CLAUDE_CONFIG_DIR: \$HOME/.claude.json is the file"
else
  fail "no CLAUDE_CONFIG_DIR: exit $rc, output \"$out\""
fi
holds "no CLAUDE_CONFIG_DIR: now off" "$dir" "$OFF"

# --- --state: asked, nothing written -------------------------------------------

dir=$(config asked '{"numStartups": 41}')
is "--state, the key unset" 0 '^on$' "$dir" --state
holds "--state leaves the key unset" "$dir" '.messageIdleNotifThresholdMs == null'
is "--state, the key at 60000" 0 '^on$' "$(config asked60 '{"messageIdleNotifThresholdMs": 60000}')" --state
is "--state, off" 0 '^off$' "$(config askedoff '{"messageIdleNotifThresholdMs": 2147483647}')" --state
is "an argument it does not know" 1 '^engine-bell-off.sh: usage: ' "$dir" --off

# --- it cannot ----------------------------------------------------------------

mkdir "$WORK/empty"
is "no file" 1 "^engine-bell-off.sh: no $WORK/empty/.claude.json, " "$WORK/empty"

dir=$(config broken '{"numStartups": 41,')
out=$(CLAUDE_CONFIG_DIR="$dir" "$OFF_SH" 2>&1)
rc=$?
if [ "$rc" != 0 ] && [ "$(cat "$dir/.claude.json")" = '{"numStartups": 41,' ] && [ -z "$(beside "$dir")" ]; then
  pass "a file that is not JSON: exit $rc, the file as it was"
else
  fail "a file that is not JSON: exit $rc, output \"$out\", left in the directory: $(beside "$dir")"
fi

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

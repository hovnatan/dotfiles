#!/usr/bin/env bash
#
# lib.sh -- what the shell tests here share. Sourced, as the first thing a
# test does after its options:
#
#   # shellcheck source=scripts/tests/lib.sh
#   . "$(dirname "$0")/lib.sh"
#
#   REPO                             the checkout the test is in
#   PTY_CLIENT                       pty_client.py: a terminal on a tmux
#                                    session (its header has the arguments)
#   log <text>                       a UTC-stamped line
#   pass <what> / fail <what>        a PASS or FAIL line; fail counts
#   until_ok <seconds> <command...>  poll until the command succeeds
#   drop_work                        for an EXIT trap: remove $WORK, or keep
#                                    it and say where when a check failed
#   finish                           the count of failures, as the last line
#                                    and as the exit status
#
# A test that records its lines as well (scripts/lib/event_log.sh's log)
# sources that too, before or after: its log is the one used.

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck disable=SC2034 # for the tests
PTY_CLIENT="$REPO/scripts/tests/pty_client.py"

failures=0
declare -F log >/dev/null || log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}

until_ok() {
  local n=$(($1 * 10))
  shift
  for _ in $(seq "$n"); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

drop_work() {
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}

finish() {
  log "$failures failure(s)"
  exit $((failures > 0))
}

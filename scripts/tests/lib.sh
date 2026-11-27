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
#   find_copy_bash <scratch dir>     COPY_BASH: a bash whose copy runs, for a
#                                    pane that runs bash under another name
#   dbus_send_stub <bin dir>         a dbus-send there that records its
#                                    calls and stands in for the bus
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

# dbus_send_stub <bin dir>: a dbus-send in that directory, for a test that
# puts it first on PATH. Each call is a line in $CALLS, the destination and
# the last argument. ListNames is answered with two zathura windows, pids 11
# and $SECOND; anything else with "boolean $ANSWER" (true unless set).
dbus_send_stub() {
  cat >"$1/dbus-send" <<'STUB'
#!/bin/sh
for arg in "$@"; do
  case "$arg" in --dest=*) dest=${arg#--dest=} ;; esac
  last=$arg
done
echo "$dest | $last" >> "$CALLS"
case "$last" in
  *ListNames)
    printf '   array [\n      string "org.freedesktop.DBus"\n      string "org.pwmt.zathura.PID-11"\n      string ":1.7"\n      string "org.pwmt.zathura.PID-%s"\n   ]\n' "$SECOND"
    ;;
  *) echo "   boolean ${ANSWER:-true}" ;;
esac
STUB
  chmod +x "$1/dbus-send"
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

# find_copy_bash <scratch dir>: COPY_BASH is a bash whose copy runs. A test
# runs copies of bash under other names, since tmux reports a pane's command
# by its file name. macOS kills a copy of a platform binary ("Killed: 9" for
# /bin/bash), which is what `command -v bash` finds when /bin comes before
# the Nix profile on PATH, as in an agent's shell: those panes then died at
# once, and later steps failed or hung on a session that was gone. So the
# first bash on PATH whose copy runs, resolved past links (a copied link
# target, not a copied wrapper).
# A new file per try: macOS remembers the kill for a file overwritten in
# place, and would kill the next copy written over it too.
find_copy_bash() {
  local dir=$1 b n=0
  COPY_BASH=
  for b in $(type -ap bash); do
    n=$((n + 1))
    b=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$b")
    cp "$b" "$dir/bash_probe$n" && ("$dir/bash_probe$n" -c :) 2>/dev/null && {
      COPY_BASH=$b
      break
    }
  done
  rm -f "$dir"/bash_probe*
  [ -n "$COPY_BASH" ] || {
    log "FAIL no bash on PATH runs when copied ($(type -ap bash | paste -sd ' ' -)); macOS kills copies of /bin/bash: put Nix's bash ahead of /bin on PATH"
    exit 1
  }
}

drop_work() {
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}

finish() {
  log "$failures failure(s)"
  exit $((failures > 0))
}

#!/usr/bin/env bash
# prefix C-s: take the client to the session whose bell is oldest, at the
# window that rang. Pressed again it goes to the next one, as the session
# just shown no longer holds its bell.
#
#   bars show " solo:1!  build:0! ", solo rang 14:02, build 14:05
#     prefix C-s -> solo, window 1
#     prefix C-s -> build, window 0
#     prefix C-s -> "no other session holds a bell"
#
# The sessions are the ones the bars mark (@bell_held, tmux.conf), the
# client's own left out. The order is by @bell_at, when each last rang
# (bell-elsewhere.sh). One without it sorts first: its bell came before
# the server ran a bell-elsewhere.sh that stamps every bell, or its hook
# has not finished yet.
#
# Runs under bash 3.2 too: run-shell finds bash on the server's PATH.
set -euo pipefail

[ "$#" -eq 3 ] || {
  echo "usage: bell-next.sh <socket> <client> <the client's session id>" >&2
  exit 2
}
socket=$1 client=$2 here=$3
# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"

best_id='' best_at='' best_held='' best_name='' count=0
while read -r id at held name; do
  [ "$held" != - ] && [ "$id" != "$here" ] || continue
  count=$((count + 1))
  [ "$at" != - ] || at=0
  if [ -z "$best_id" ] || [ "$at" -lt "$best_at" ]; then
    best_id=$id best_at=$at best_held=$held best_name=$name
  fi
done < <(tmux -S "$socket" list-sessions \
  -F '#{session_id} #{?@bell_at,#{@bell_at},-} #{?#{E:@bell_held},#{E:@bell_held},-} #{session_name}')

if [ -z "$best_id" ]; then
  tmux -S "$socket" display-message -c "$client" "no other session holds a bell"
  event_log_note tmux_hooks "bell-next ${client#/dev/}: no other session holds a bell"
  exit 0
fi

# "1!,3!" -> 1: the first window the marker names.
window=${best_held%%[!0-9]*}
[ -n "$window" ] || {
  echo "bell-next.sh: session $best_name holds '$best_held', which names no window" >&2
  exit 1
}
tmux -S "$socket" switch-client -c "$client" -t "$best_id:$window"
if [ "$best_at" = 0 ]; then when="at a time not recorded"; else when="$(($(date +%s) - best_at))s ago"; fi
event_log_note tmux_hooks "bell-next ${client#/dev/}: -> $best_name:$window (rang $when, $count held)"

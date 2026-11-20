#!/usr/bin/env bash
# prefix C-s: take the client to a session holding a bell, at the window
# that rang, the one that rang longest ago first. Pressed again it goes to
# the next, as a window just shown no longer holds its bell. With no bell
# left it goes to the session used last.
#
#   bars show " solo:1!  build:0! ", solo rang 14:02, build 14:05
#     prefix C-s -> solo, window 1
#     prefix C-s -> build, window 0
#     prefix C-s -> notes
#
# Which sessions hold a bell, their order and which was used last are
# bell-sessions.sh's, shared with prefix s (session-pick.sh). A session
# another tab shows is left out of the way back.
#
# Runs under bash 3.2 too: run-shell finds bash on the server's PATH.
set -euo pipefail

[ "$#" -eq 3 ] || {
  echo "usage: bell-next.sh <socket> <client> <the client's session id>" >&2
  exit 2
}
socket=$1 client=$2 here=$3
who="bell-next ${client#/dev/}"
# shellcheck source=home/.config/tmux/bell-sessions.sh
. "${0%/*}/bell-sessions.sh"
now=${EPOCHSECONDS:-$(date +%s)}

list=$(bell_sessions "$socket" "$here") || exit 1
count=0 bell='' back=''
while IFS='|' read -r id window attached used at held _ name; do
  if [ -n "$held" ]; then
    count=$((count + 1))
    [ -n "$bell" ] || bell=$id:$window bell_at=$at bell_name=$name:$window
  elif [ "$attached" = 0 ] && [ -z "$back" ]; then
    back=$id back_used=$used back_name=$name
  fi
done <<<"$list"

if [ -n "$bell" ]; then
  tmux -S "$socket" switch-client -c "$client" -t "$bell"
  if [ "$bell_at" = 0 ]; then when="at a time not recorded"; else when="$((now - bell_at))s ago"; fi
  event_log_note tmux_hooks "$who: -> $bell_name (rang $when, $count held)"
elif [ -n "$back" ]; then
  tmux -S "$socket" switch-client -c "$client" -t "$back"
  event_log_note tmux_hooks "$who: no bell held, -> $back_name (used $((now - back_used))s ago)"
else
  event_log_note tmux_hooks "$who: no bell held, and no detached session to go to"
fi

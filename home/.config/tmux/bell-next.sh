#!/usr/bin/env bash
# prefix C-s: take the client to a session holding a bell, at the window
# that rang, the one that rang longest ago first. Pressed again it goes to
# the next, as a window just shown no longer holds its bell. With no bell
# left it goes to the session used last.
#
#   bars show " solo:1!  build:0! ", solo rang 14:02, build 14:05
#     prefix C-s -> solo, window 1
#     prefix C-s -> build, window 0
#     prefix C-s -> notes ("no bell held: back to notes")
#
# The sessions are the ones the bars mark (@bell_held, tmux.conf), and the
# client's own for a bell in one of its windows out of view. The order is by
# @bell_at, when each last rang (bell-elsewhere.sh), so one that rings again
# goes to the back. One without it goes first: its bell's hook runs in the
# background and may not have stamped it yet.
#
# Used last is the first row of prefix s (tmux.conf) that no client is on:
# by #{session_activity}, a client's last input in the session, or its
# creation for one never attached to. A session another tab shows is left
# out.
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
who="bell-next ${client#/dev/}"
now=${EPOCHSECONDS:-$(date +%s)}

bell_id='' bell_at='' bell_held='' bell_name='' count=0
back_id='' back_used='' back_name=''
# The name last: it may hold the separator.
while IFS='|' read -r id attached used at held alerts name; do
  # Its own session's @bell is of the window the client is looking at, and
  # the hooks that clear it may still be running after a switch.
  [ "$id" != "$here" ] || held=$alerts
  if [ -n "$held" ]; then
    count=$((count + 1))
    at=${at:-0}
    if [ -z "$bell_id" ] || [ "$at" -lt "$bell_at" ]; then
      bell_id=$id bell_at=$at bell_held=$held bell_name=$name
    fi
  elif [ "$attached" = 0 ]; then
    if [ -z "$back_id" ] || [ "$used" -gt "$back_used" ]; then
      back_id=$id back_used=$used back_name=$name
    fi
  fi
done < <(tmux -S "$socket" list-sessions \
  -F '#{session_id}|#{session_attached}|#{session_activity}|#{@bell_at}|#{E:@bell_held}|#{session_alerts}|#{session_name}')

if [ -n "$bell_id" ]; then
  # "1!,3!" -> 1: the first window the marker names.
  window=${bell_held%%[!0-9]*}
  [ -n "$window" ] || {
    msg="session $bell_name holds '$bell_held', which names no window"
    event_log_note tmux_hooks "$who: FAILED, $msg"
    echo "bell-next.sh: $msg" >&2
    exit 1
  }
  tmux -S "$socket" switch-client -c "$client" -t "$bell_id:$window"
  if [ "$bell_at" = 0 ]; then when="at a time not recorded"; else when="$((now - bell_at))s ago"; fi
  event_log_note tmux_hooks "$who: -> $bell_name:$window (rang $when, $count held)"
elif [ -n "$back_id" ]; then
  tmux -S "$socket" switch-client -c "$client" -t "$back_id" \; \
    display-message -c "$client" "no bell held: back to $back_name"
  event_log_note tmux_hooks "$who: no bell held, -> $back_name (used $((now - back_used))s ago)"
else
  msg="no bell held, and no detached session to go back to"
  tmux -S "$socket" display-message -c "$client" "$msg"
  event_log_note tmux_hooks "$who: $msg"
fi

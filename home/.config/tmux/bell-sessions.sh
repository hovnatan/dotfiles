#!/usr/bin/env bash
# bell-sessions.sh -- the sessions in the order prefix C-s (bell-next.sh) and
# prefix s (session-pick.sh) take them. Sourced by both, which set $who, the
# name their log lines start with.
#
#   stop <message>
#       a failure: in the log and on stderr, exit 1
#   bell_sessions <socket> <the client's session id>
#       a line per session, the name last as it may hold the separator:
#         <id>|<window>|<attached>|<used>|<rang>|<held>|<windows>|<name>
#         $3|1|0|1795200000|1795199000|1!,3!|4|notes
#         $1||1|1795200100|||2|mail
#       First the sessions holding a bell, the one that rang longest ago on
#       top: <held> is the marker of the bars (@bell_held, tmux.conf),
#       <window> the first it names, <rang> its @bell_at (bell-elsewhere.sh),
#       0 for a bell not stamped yet, as its hook runs in the background. So
#       a session that rings again goes to the back, and an unstamped one
#       first. Then the rest, <held> empty, the one used last on top: by
#       #{session_activity}, a client's last input in the session, or its
#       creation for one never attached to.
#       The client's own session holds its #{session_alerts} alone: its
#       @bell is of the window the client is looking at, and the hooks that
#       clear it may still be running after a switch.
#
# Runs under bash 3.2 too: run-shell finds bash on the server's PATH.

# shellcheck source=scripts/lib/event_log.sh
. "${BASH_SOURCE[0]%/*}/../../../scripts/lib/event_log.sh"

stop() {
  event_log_note tmux_hooks "${who:?the script sourcing bell-sessions.sh sets it}: FAILED, $1"
  echo "${0##*/}: $1" >&2
  exit 1
}

bell_sessions() {
  local list id attached used at held alerts windows name window
  list=$(tmux -S "$1" list-sessions \
    -F '#{session_id}|#{session_attached}|#{session_activity}|#{@bell_at}|#{E:@bell_held}|#{session_alerts}|#{session_windows}|#{session_name}') \
    || stop "tmux could not list the sessions of $1"
  # Two sort keys ahead of each line, cut off again: 0 and when it rang, or
  # 1 and when it was used, negated for the latest first. -s: equal ones
  # stay in tmux's order.
  while IFS='|' read -r id attached used at held alerts windows name; do
    [ "$id" != "$2" ] || held=$alerts
    window=''
    if [ -n "$held" ]; then
      # "1!,3!" -> 1
      window=${held%%[!0-9]*}
      [ -n "$window" ] || stop "session $name holds '$held', which names no window"
      at=${at:-0}
      printf '0|%s|' "$at"
    else
      printf '1|%s|' "-$used"
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$window" "$attached" "$used" "$at" "$held" "$windows" "$name"
  done <<<"$list" | sort -s -t '|' -k1,1n -k2,2n | cut -d '|' -f3-
}

#!/usr/bin/env bash
# Tell the terminals elsewhere on the server about a bell in a session that
# nobody is looking at. tmux passes a bell only to the clients of the session
# it rang in (bell-action), and a client in a background tab or window is no
# one looking: a Claude Code or long command finishing there reached no one.
#
#   window 1 of session "solo" rings              (alert-bell, every bell)
#     -> bell-elsewhere.sh <socket> $3 solo 1 <window name>
#     -> a client of solo has focus?  yes -> exit: tmux's own bell reached it
#                                     no  (none attached, or all unfocused):
#     -> @bell "1!" on solo, for the status-left marker in tmux.conf
#     -> display-message on each terminal client of another session, 5 s:
#          bell: solo:1 * vm/fix
#     -> ~/.dotfiles/.logs/<UTC day>_tmux_hooks/events.log
#        2026-11-10T02:10:00Z bell session=solo window=1 (* vm/fix): unwatched
#          (1 client, none focused), shown to /dev/ttys003
#
# Why @bell: tmux marks a bell itself (#{session_alerts}) only in a window no
# client shows; one in the window an unfocused tab shows leaves no trace.
# tmux.conf's client-attached, client-session-changed and client-focus-in
# hooks unset it once a client of the session is attached, switched to it, or
# focused.
#
# "Focused" is tmux's client flag, from the terminal's focus reports
# (focus-events on). A terminal that never reports focus stays focused from
# its attach, so its session counts as watched: as before this script.
#
# Control-mode clients (scripts/tmux_history.py's tracker, iTerm2 -CC) have no
# status line to show a message on and no focus, so they are skipped. A client
# that detaches between the listing and its message fails the script: the
# hook reports the error, and the log names the client.
#
# Runs under bash 3.2 too: run-shell finds bash on the server's PATH.
set -euo pipefail

[ "$#" -eq 5 ] || {
  echo "usage: bell-elsewhere.sh <socket> <session id> <session name> <window index> <window name>" >&2
  exit 2
}
socket=$1 id=$2 session=$3 window=$4 name=$5
t() { tmux -S "$socket" "$@"; }

# Watched: a terminal client of this session has focus. Most bells end here
# (the shell rings after every command over 1 s), so nothing is logged.
# An assignment, not a substitution in a redirect: set -e sees it fail.
own=$(t list-clients -t "$id" -F '#{client_control_mode},#{client_flags},')
n=0
while IFS= read -r flags; do
  case $flags in
    "" | 1,*) continue ;;
    *,focused,*) exit 0 ;;
  esac
  n=$((n + 1))
done <<<"$own"

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"
case $n in
  0) why="no client" ;;
  1) why="1 client, none focused" ;;
  *) why="$n clients, none focused" ;;
esac
what="bell session=$session window=$window ($name): unwatched ($why)"

# "1!", as tmux writes #{session_alerts}: a bare "0" reads as false in a
# format's conditional, and window 0's marker never showed.
t set-option -t "$id" @bell "$window!"

# display-message expands formats in its text: a window name holding "#"
# (Claude Code's titles may) is shown as typed, not expanded.
msg="bell: $session:$window $name"
msg=${msg//#/##}

clients=$(t list-clients -F '#{client_name}	#{client_control_mode}	#{session_id}')
shown=
while IFS=$'\t' read -r client control sid; do
  [ -n "$client" ] || continue # no clients: the listing is one empty line
  [ "$control" = 1 ] && continue
  [ "$sid" = "$id" ] && continue # its own clients got tmux's bell
  t display-message -c "$client" -d 5000 "$msg" || {
    event_log_note tmux_hooks "$what: FAILED: display-message to $client"
    exit 1
  }
  shown="$shown $client"
done <<<"$clients"
event_log_note tmux_hooks "$what, shown to${shown:- no client}"

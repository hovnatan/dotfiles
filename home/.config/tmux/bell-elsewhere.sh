#!/usr/bin/env bash
# Tell every terminal on the server about a bell in a session nobody is
# attached to. tmux passes a bell only to the clients of the session it rang
# in (bell-action), so a Claude Code or long command finishing in a detached
# session otherwise reaches no one.
#
#   window 1 of session "solo" (no client) rings
#     -> alert-bell hook (tmux.conf; fires only when session_attached is 0)
#     -> bell-elsewhere.sh <socket> solo 1 <window name>
#     -> display-message on each terminal client:  bell: solo:1 * vm/fix
#     -> ~/.dotfiles/.logs/<UTC day>_tmux_hooks/events.log
#        2026-11-10T02:10:00Z bell session=solo window=1 (* vm/fix): shown to /dev/ttys003
#
# The status-left marker in tmux.conf ("solo:1!") is the lasting half: it
# stays until the window is looked at, this message goes after 5 s.
#
# Control-mode clients (scripts/tmux_history.py's tracker, iTerm2 -CC) have
# no status line to show a message on, so they are skipped. A client that
# detaches between the listing and its message fails the script: the hook
# reports the error, and the log names the client.
#
# Runs under bash 3.2 too: run-shell finds bash on the server's PATH.
set -euo pipefail

[ "$#" -eq 4 ] || {
  echo "usage: bell-elsewhere.sh <socket> <session> <window index> <window name>" >&2
  exit 2
}
socket=$1 session=$2 window=$3 name=$4

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"
what="bell session=$session window=$window ($name)"

# display-message expands formats in its text: a window name holding "#"
# (Claude Code's titles may) is shown as typed, not expanded.
msg="bell: $session:$window $name"
msg=${msg//#/##}

# An assignment, not a substitution in the redirect: set -e sees it fail.
clients=$(tmux -S "$socket" list-clients -F '#{client_name}	#{client_control_mode}')
shown=
while IFS=$'\t' read -r client control; do
  [ -n "$client" ] || continue # no clients: the listing is one empty line
  [ "$control" = 1 ] && continue
  tmux -S "$socket" display-message -c "$client" -d 5000 "$msg" || {
    event_log_note tmux_hooks "$what: FAILED: display-message to $client"
    exit 1
  }
  shown="$shown $client"
done <<<"$clients"
event_log_note tmux_hooks "$what: shown to${shown:- no client}"

#!/usr/bin/env bash
# Tell the terminals elsewhere on the server about a bell in a session that
# nobody is looking at. tmux passes a bell only to the clients of the session
# it rang in (bell-action), and a client in a background tab or window is no
# one looking: a Claude Code or long command finishing there reached no one.
#
#   window 1 of session "solo" rings              (alert-bell, every bell)
#     -> bell-elsewhere.sh <socket> $3 solo 1 <window name>
#     -> a client of solo focused, with input in the last 30 min?
#          yes -> log "watched (...)", exit: tmux's own bell reached it
#          no  (none attached, all unfocused, or focus gone stale):
#     -> @bell "1!" and @bell_at <epoch> on solo, for the bar's @bell_marker
#     -> display-message on each terminal client of another session, 5 s:
#          bell: solo:1 * vm/fix
#     -> ~/.dotfiles/.logs/<UTC day>_tmux_hooks/events.log, with what tmux
#        knew of solo's clients, so a wrong verdict explains itself:
#        2026-11-10T02:10:00Z bell session=solo window=1 (* vm/fix): unwatched
#          (ttys002 not focused, input 41s ago), shown to /dev/ttys003
#
# Why @bell: tmux marks a bell itself (#{session_alerts}) only in a window no
# client shows; one in the window an unfocused tab shows leaves no trace.
# tmux.conf's client-attached, client-session-changed and client-focus-in
# hooks unset it once a client of the session is attached, switched to it, or
# focused. A terminal whose focus reports stopped sends no focus-in, so the
# marker also hides once the session has input after @bell_at
# (#{session_activity}: a client's keys, mouse and focus reports, not pane
# output; tested 2026-11-10, tmux 3.8).
#
# Focus is what ntfy-stop.sh (home/.claude/) learned to distrust, and this
# follows its rule (watched() there):
#   - a locked or sleeping Mac freezes the terminal without a focus-out, and
#     a dropped ssh leaves its client behind for a while: the flag stays
#     "focused". A frozen terminal sends no input either, so a focused client
#     counts only with input in the last BELL_STALE_SECONDS (default 1800,
#     ntfy's STALE_SECONDS). Coming back counts as input: the focus-in does.
#   - tmux asks for focus reports once, at attach, so a terminal that resets
#     its modes later stops sending them: the flag freezes either way.
#     Stuck focused is the case above; stuck unfocused is the input rule of
#     the marker. The log shows it as "not focused, input 2s ago".
# A terminal that never reports focus stays focused from its attach, so its
# session counts as watched while someone types there.
#
# Control-mode clients (scripts/tmux_history.py's tracker) have no
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
stale=${BELL_STALE_SECONDS:-1800}
t() { tmux -S "$socket" "$@"; }
# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"
now=$(date +%s)

# Watched: a terminal client of this session focused, with fresh input. The
# evidence reads as ntfy-stop.sh's: "ttys002 focused, input 3s ago; ...".
# An assignment, not a substitution in a redirect: set -e sees it fail.
own=$(t list-clients -t "$id" -F '#{client_control_mode} #{client_activity} #{client_name} #{client_flags}')
watched=''
evidence=''
while read -r control activity client flags; do
  [ -n "$client" ] || continue # no clients: the listing is one empty line
  [ "$control" = 1 ] && continue
  age=$((now - activity))
  case ,$flags, in
    *,focused,*)
      state=focused
      if [ "$age" -lt "$stale" ]; then watched=1; fi
      ;;
    *) state="not focused" ;;
  esac
  evidence="${evidence:+$evidence; }${client#/dev/} $state, input ${age}s ago"
done <<<"$own"
what="bell session=$session window=$window ($name)"
if [ -n "$watched" ]; then
  event_log_note tmux_hooks "$what: watched ($evidence)"
  exit 0
fi
what="$what: unwatched (${evidence:-no client})"

# "1!", as tmux writes #{session_alerts}: a bare "0" reads as false in a
# format's conditional, and window 0's marker never showed.
t set-option -t "$id" @bell "$window!"
t set-option -t "$id" @bell_at "$now"

# display-message expands formats in its text: a window name holding "#"
# (Claude Code's titles may) is shown as typed, not expanded.
msg="bell: $session:$window $name"
msg=${msg//#/##}

clients=$(t list-clients -F '#{client_name}	#{client_control_mode}	#{session_id}')
shown=
while IFS=$'\t' read -r client control sid; do
  [ -n "$client" ] || continue
  [ "$control" = 1 ] && continue
  [ "$sid" = "$id" ] && continue # its own clients got tmux's bell
  t display-message -c "$client" -d 5000 "$msg" || {
    event_log_note tmux_hooks "$what: FAILED: display-message to $client"
    exit 1
  }
  shown="$shown $client"
done <<<"$clients"
event_log_note tmux_hooks "$what, shown to${shown:- no client}"

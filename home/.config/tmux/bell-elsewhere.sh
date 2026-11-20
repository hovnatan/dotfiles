#!/usr/bin/env bash
# Mark a bell in a session that nobody is looking at, for the bars of the
# other sessions to show. tmux passes a bell only to the clients of the
# session it rang in (bell-action), and a client in a background tab or window
# is no one looking: a Claude Code or long command finishing there reached no
# one.
#
#   window 1 of session "solo" rings              (alert-bell, every bell)
#     -> bell-elsewhere.sh <socket> $3 solo 1 <window name>
#     -> a client of solo focused, with input in the last 30 min?
#          yes -> log "watched (...)", exit: tmux's own bell reached it
#          no  (none attached, all unfocused, or focus gone stale):
#     -> @bell "1!" and @bell_at <epoch> on solo, which the bar's
#        @bell_marker (tmux.conf) draws as " solo:1! " first on the right of
#        every other session's bar, until solo is looked at
#     -> ~/.dotfiles/.logs/<UTC day>_tmux_hooks/events.log, with what tmux
#        knew of solo's clients, so a wrong verdict explains itself:
#        2026-11-10T02:10:00Z bell session=solo window=1 (* vm/fix): unwatched
#          (ttys002 not focused, input 41s ago), marked
#
# The marker is all there is. Until 2026-11-19 each terminal of another
# session was also sent a 5 s message "bell: solo:1 * vm/fix", which took
# over its whole bar (window list, title and clock) at every bell.
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
# Focus is what the session-done mod's push (home/.claude/mods/session-done/)
# learned to distrust, and this follows its rule (watched() in its
# tmux-watch.sh):
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
# Control-mode clients (scripts/tmux_history.py's tracker) have no focus to
# report and no one behind them, so they do not count as someone watching.
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
# evidence reads as tmux-watch.sh's: "ttys002 focused, input 3s ago; ...".
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

# "1!", as tmux writes #{session_alerts}: a bare "0" reads as false in a
# format's conditional, and window 0's marker never showed.
t set-option -t "$id" @bell "$window!"
t set-option -t "$id" @bell_at "$now"
event_log_note tmux_hooks "$what: unwatched (${evidence:-no client}), marked"

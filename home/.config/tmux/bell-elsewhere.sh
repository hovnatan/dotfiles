#!/usr/bin/env bash
# Mark a bell in a session that nobody is looking at, for the bars of the
# other sessions to show. tmux passes a bell only to the clients of the
# session it rang in (bell-action), and a client in a background tab or window
# is no one looking: a Claude Code or long command finishing there reached no
# one.
#
#   window 1 of session "solo" rings              (alert-bell, every bell)
#     -> bell-elsewhere.sh <socket> $3 solo 1 <window name>
#     -> is anybody on solo? (scripts/tmux_watched.sh session)
#          yes -> log "watched (...)", exit: tmux's own bell reached it
#          no  (none attached, all unfocused, or focus gone stale):
#     -> @bell "1!" and @bell_at <epoch> on solo, which the bar's
#        @bell_marker (tmux.conf) draws as " solo:1! " first on the right of
#        every other session's bar, until solo is looked at; prefix C-s
#        goes there (bell-next.sh, the oldest @bell_at first)
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
# Watched is scripts/tmux_watched.sh's rule (its header has it), asked for
# the session whole. The session-done mod's push asks it about claude's pane
# alone, so the two may differ on one bell: a client on another window of
# the session is on the session, and has not seen the turn.
#
# Runs under bash 3.2 too: run-shell finds bash on the server's PATH.
set -euo pipefail

[ "$#" -eq 5 ] || {
  echo "usage: bell-elsewhere.sh <socket> <session id> <session name> <window index> <window name>" >&2
  exit 2
}
socket=$1 id=$2 session=$3 window=$4 name=$5
SCRIPTS="${0%/*}/../../../scripts"
# shellcheck source=scripts/lib/event_log.sh
. "$SCRIPTS/lib/event_log.sh"
what="bell session=$session window=$window ($name)"
# A builtin from bash 5 on; 3.2 forks date.
now=${EPOCHSECONDS:-$(date +%s)}

# The verdict by the exit status, the evidence on stdout either way:
# "ttys002 focused, input 3s ago; ...". An assignment, so the status is the
# script's.
rc=0
evidence=$("$SCRIPTS/tmux_watched.sh" -S "$socket" session "$id") || rc=$?
case $rc in
  0)
    # The time of every bell, for bell-next.sh's order: a watched session
    # still holds this one where its window is out of view. An @bell that
    # input had hidden goes, as under the new time it would show again.
    tmux -S "$socket" set-option -t "$id" @bell_at "$now" \; \
      set-option -qu -t "$id" @bell
    event_log_note tmux_hooks "$what: watched ($evidence)"
    ;;
  1)
    # "1!", as tmux writes #{session_alerts}: a bare "0" reads as false in a
    # format's conditional, and window 0's marker never showed.
    tmux -S "$socket" set-option -t "$id" @bell "$window!" \; \
      set-option -t "$id" @bell_at "$now"
    event_log_note tmux_hooks "$what: unwatched ($evidence), marked"
    ;;
  # Killed between its bell and this hook: nothing left to mark.
  2) event_log_note tmux_hooks "$what: session gone, not marked" ;;
  *)
    # tmux shows a run-shell that fails as "... returned 1" on the client.
    event_log_note tmux_hooks "$what: FAILED, tmux_watched.sh exit $rc: $evidence"
    echo "bell-elsewhere.sh: tmux_watched.sh exit $rc: $evidence" >&2
    exit 1
    ;;
esac

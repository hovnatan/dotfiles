#!/usr/bin/env bash
# tmux-watch.sh -- what tmux knows of the pane a claude session runs in, for
# the push of the session-done mod it belongs to (hooks/push.ts), which
# decides whether a finished turn was seen. The mod hands over claude's $TMUX
# and $TMUX_PANE as they are and reads the answer off the exit status; every
# tmux detail, $TMUX's layout and each format string, is in this file.
#
#   tmux-watch.sh watched <$TMUX> <pane>
#       0  watched
#       1  not watched; stdout: what tmux knew of the clients (see clients())
#       2  the server or claude's pane is gone
#       3  tmux failed otherwise; stdout: "tmux -S <socket>: <its message>"
#   tmux-watch.sh session <$TMUX> <pane>
#       0  stdout: the name of the session the pane is in now
#       2  gone, 3 failed, as above
#
#   $TMUX = "/tmp/tmux-501/default,52401,3" -> socket /tmp/tmux-501/default,
#   session id 3 ($3 to tmux)
#
# The session is given by its id (the third field of $TMUX, stable across
# renames for the server's lifetime), and claude's pane by $TMUX_PANE: a
# session can hold more windows than claude's (nvim, a shell), and a client
# typing in one of those has not seen the turn. On screen means the
# session's current window is the pane's, and that window is not zoomed
# onto another of its panes. The current window is per session in tmux, so
# every client of a session agrees on it. The pane's window is looked up at
# every call, as break-pane / join-pane move a pane between windows and
# move-window / join-pane between sessions; a client counts by the window
# it shows, whatever session it is attached to:
#
#   session $3 (current window @2)
#     @1  claude %4        <- the turn finished here
#     @2  nvim             <- pts/1, focused: not watching %4 -> exit 1
#
# Runs on stock macOS too (bash 3.2): builtins and tmux alone.
set -u

STALE_SECONDS="${CLAUDE_NTFY_STALE_SECONDS:-1800}"

# clients <socket> <session-id> <pane>: print what tmux knows of the
# session's clients, the evidence behind a verdict of "unwatched":
#   "pts/1 not focused, input 14s ago; pts/5 focused, input 2400s ago"
#   "pts/1 focused, input 3s ago, on window 2 (claude's is 0)"
#   "pts/1 focused, input 3s ago, claude's window zoomed onto another pane"
#   "no client attached"
# The window is named only when it is not claude's, so a session of one
# window reads as before. Input seconds ago with no focus is a
# contradiction worth seeing: somebody is at that terminal, and its focus
# reports are not arriving (a terminal that resets its modes after the
# attach sends none again; 2026-09-30).
# The clients listed are those of the session claude's pane is in now --
# the one claude started in, unless the pane moved -- and those of that
# session once the pane is gone. Best effort: this is evidence for a log
# line, and a tmux failure here has already been reported by watched().
clients() {
  local now tty flags activity win idx out="" own="" ownidx="" in="\$$2" zoomed=""
  now=${EPOCHSECONDS:-$(date +%s)}
  read -r own ownidx in zoomed <<PANE
$(tmux -S "$1" display-message -p -t "$3" '#{window_id} #{window_index} #{session_id} #{?#{&&:#{window_zoomed_flag},#{!=:#{pane_active},1}},zoomed,}' 2>/dev/null)
PANE
  in=${in:-\$$2}
  while read -r tty flags activity win idx; do
    [ -n "$tty" ] || continue
    case ",$flags," in *,focused,*) flags=focused ;; *) flags="not focused" ;; esac
    out="${out:+$out; }${tty#/dev/} $flags, input $((now - activity))s ago"
    if [ -z "$own" ]; then
      out="$out, claude's pane $3 gone"
    elif [ "$win" != "$own" ]; then
      out="$out, on window $idx (claude's is $ownidx)"
    elif [ -n "$zoomed" ]; then
      out="$out, claude's window zoomed onto another pane"
    fi
  done <<LIST
$(tmux -S "$1" list-clients -t "$in" -F '#{client_tty} #{client_flags} #{client_activity} #{window_id} #{window_index}' 2>/dev/null)
LIST
  printf '%s\n' "${out:-no client attached}"
}

# tmux_ask <socket> <tmux args...>: run tmux, its output in $tmux_out.
# Status 0, 2 if the server is gone (the messages tmux prints when nothing
# listens on the socket), 3 on any other failure, the message in $tmux_out
# -- a client too old for the server, say -- which must not read as "gone":
# that would cancel a push without a word.
tmux_ask() {
  local socket=$1
  shift
  tmux_out=$(tmux -S "$socket" "$@" 2>&1) && return 0
  case $tmux_out in
    "no server running on "* | "error connecting to "*"(No such file or directory)" | \
      "error connecting to "*"(Connection refused)") return 2 ;;
  esac
  return 3
}

# watched <socket> <session-id> <pane>: status 0 if claude's pane is on
# screen (its window current in its session, not zoomed onto another pane)
# and a client showing that window is focused AND produced input within
# STALE_SECONDS, 1 if not, 2 if the server or the pane is gone, 3 if tmux
# failed otherwise (tmux_ask; its message in $tmux_out). Any client counts,
# not only those of the session claude started in: a pane moved to another
# session is watched by that session's clients. The freshness bound exists
# because a locked/asleep Mac freezes the outer terminal without ever
# sending a focus-out, leaving the flag stuck at "focused" -- but a frozen
# terminal also sends no input, so activity ages past the bound and pushes
# resume (a turn ending within the first STALE_SECONDS of the lock stays
# suppressed; that is the heuristic's floor). Coming back refreshes activity
# with no typing needed: the focus-in event itself counts as client input
# (verified), as do mouse scrolls. tmux evaluates the whole predicate itself
# via the -f filter; the shell only tests whether any client matched.
watched() {
  local now win
  now=${EPOCHSECONDS:-$(date +%s)} # builtin on bash 5+; forks on macOS 3.2
  # "@2", or "@2 zoomed" while the window shows another of its panes; empty
  # once the pane is gone (display-message does not fail on a missing
  # target, tmux 3.7c)
  tmux_ask "$1" display-message -p -t "$3" \
    '#{window_id}#{?#{&&:#{window_zoomed_flag},#{!=:#{pane_active},1}}, zoomed,}' || return
  win=$tmux_out
  [ -n "$win" ] || return 2
  case $win in *" zoomed") return 1 ;; esac
  tmux_ask "$1" list-clients \
    -f "#{&&:#{&&:#{m:*focused*,#{client_flags}},#{e|<:$((now - STALE_SECONDS)),#{client_activity}}},#{==:#{window_id},$win}}" \
    -F w || return
  [ -n "$tmux_out" ]
}

usage() {
  echo "tmux-watch.sh: usage: tmux-watch.sh watched <\$TMUX> <pane> | session <\$TMUX> <pane>" >&2
  exit 64
}

case "${1:-} $#" in
  "watched 3" | "session 3") ;;
  *) usage ;;
esac

# The server pid in the middle is cut from the right, so a socket path with
# a comma in it stays whole.
sid=${2##*,}
socket=${2%,*}
socket=${socket%,*}
pane=$3

# failed: tmux's own message, with the socket it was asked on.
failed() { printf 'tmux -S %s: %s\n' "$socket" "$tmux_out"; }

case $1 in
  watched)
    watched "$socket" "$sid" "$pane"
    rc=$?
    case $rc in
      1) clients "$socket" "$sid" "$pane" ;;
      3) failed ;;
    esac
    exit "$rc"
    ;;
  session)
    # The pane's session now: it may have moved since the turn ended. An
    # empty name is a pane gone (display-message does not fail on one).
    tmux_ask "$socket" display-message -p -t "$pane" '#{session_name}'
    rc=$?
    [ "$rc" = 0 ] && [ -z "$tmux_out" ] && rc=2
    case $rc in
      0) printf '%s\n' "$tmux_out" ;;
      3) failed ;;
    esac
    exit "$rc"
    ;;
esac

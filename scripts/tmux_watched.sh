#!/usr/bin/env bash
# tmux_watched.sh -- is somebody looking? The one rule for "a tmux client
# counts as a person who is there", and the two questions asked with it:
#
#   tmux_watched.sh [-S <socket>] pane <pane id>
#       is this pane on somebody's screen?   asked by the session-done mod,
#       for its ntfy push (home/.claude/mods/session-done/hooks/push.ts)
#   tmux_watched.sh [-S <socket>] session <session id>
#       is anybody on this session, at any of its windows?   asked by
#       home/.config/tmux/bell-elsewhere.sh, for the bell marker on the bars
#   tmux_watched.sh [-S <socket>] session-name <pane id>
#       the name of the session the pane is in now, for the push's title
#
#   The server is the one -S names, as tmux's own -S; with none it is the
#   caller's, which tmux finds by $TMUX. Nothing but tmux reads $TMUX's
#   layout: a caller inside a pane passes no socket (the mod), and one that
#   tmux runs is handed #{socket_path} (the bell's hook).
#
#   exit 0  watched; for session-name, the name on stdout
#        1  not watched
#        2  gone: the server, the pane or the session
#        3  tmux failed otherwise; stdout: "tmux: <its message>", or
#           "tmux -S <socket>: <its message>" with a socket named
#   pane and session print the evidence with 0 and 1 alike, what tmux knew of
#   the clients, so a verdict in a log explains itself:
#     "ttys002 focused, input 3s ago"
#     "pts/1 not focused, input 14s ago; pts/5 focused, input 2400s ago"
#     "pts/1 focused, input 3s ago, on window 2 (the pane's is 0)"
#     "pts/1 focused, input 3s ago, the pane's window zoomed onto another pane"
#     "no client attached"
#
# One rule, two widths. The two callers want different things and may
# disagree about one moment, rightly:
#
#   session $3 (current window @2)
#     @1  claude %4        <- a turn ended here, and the bell rang
#     @2  nvim             <- ttys001, focused, typing
#
#   session $3 -> 0: ttys001 is on the session, and its own bar flags the
#                    bell in window 1; no marker for the other bars
#   pane %4    -> 1: nobody has seen the turn; the push's wait starts
#
# The rule: a client is there when all of these hold.
#   - It is focused. tmux asks the terminal for focus reports once, at
#     attach; one that never reports stays focused from then on.
#   - It gave input within TMUX_WATCHED_STALE_SECONDS (default 1800). Focus
#     alone is not believed: a locked or sleeping Mac freezes the terminal
#     without a focus-out, and a dropped ssh leaves its client behind for a
#     while, so the flag stays "focused". A frozen terminal sends no input
#     either. Coming back counts as input with no typing: the focus-in does,
#     and so does a mouse scroll. The floor of this: a bell or a turn's end
#     within the first 30 minutes of a lock still reads as watched.
#     "not focused, input 2s ago" in the evidence is the other way round:
#     somebody is at that terminal and its focus reports are not arriving
#     (a terminal that reset its modes after the attach; 2026-09-30).
#   - It is in scope:
#       session   attached to that session
#       pane      showing the pane's window, which is not zoomed onto
#                 another of its panes. The window is looked up at every
#                 call, as break-pane, join-pane and move-window move a pane
#                 between windows and sessions, and a client counts by the
#                 window it shows, whatever session it is attached to. The
#                 current window is per session in tmux, so every client of
#                 a session agrees on it.
#
# One tmux call a question, for where the target is and for every client of
# the server, judged here: this runs at every bell, and every 5 s while a
# push waits. Runs on stock macOS too (bash 3.2, which run-shell finds on
# the server's PATH): builtins and tmux alone.
set -u

STALE=${TMUX_WATCHED_STALE_SECONDS:-1800}

usage() {
  echo "tmux_watched.sh: usage: tmux_watched.sh [-S <socket>] pane <pane id> | session <session id> | session-name <pane id>" >&2
  exit 64
}

tmux=(tmux)
if [ "${1:-}" = -S ]; then
  [ $# -ge 2 ] || usage
  tmux=(tmux -S "$2")
  shift 2
fi
case "${1:-} $#" in
  "pane 2" | "session 2" | "session-name 2") ;;
  *) usage ;;
esac
what=$1 target=$2

# Where the target is now. display-message does not fail on a target that is
# gone, it expands every format to nothing (tmux 3.8). The name is last: it
# is the one field that may hold a "|".
#   pane %4     -> "$3|@1|0||solo"   or "$3|@1|0|zoomed|solo" while its window
#                  shows another of its panes
#   session $3  -> "$3|@2|1||solo"   its current window, which is not asked
#   gone        -> "||||"
WHERE='#{session_id}|#{window_id}|#{window_index}|#{?#{&&:#{window_zoomed_flag},#{!=:#{pane_active},1}},zoomed,}|#{session_name}'
# Every client of the server, one a line; a server with none prints nothing:
#   "$3|@2|1|1795149619|/dev/ttys001|attached,focused,UTF-8"
CLIENTS='#{session_id}|#{window_id}|#{window_index}|#{client_activity}|#{client_name}|#{client_flags}'

# Both in one call, the target's line first. A failure ends this script:
# with 2 if the server is gone (the messages tmux prints when nothing
# listens on the socket), with 3 and tmux's message on any other, a client
# too old for the server, say. That one must not read as "gone": a caller
# told so drops what it had to say without a word.
if [ "$what" = session-name ]; then
  out=$("${tmux[@]}" display-message -p -t "$target" "$WHERE" 2>&1)
else
  out=$("${tmux[@]}" display-message -p -t "$target" "$WHERE" \; list-clients -F "$CLIENTS" 2>&1)
fi || {
  case $out in
    "no server running on "* | "error connecting to "*"(No such file or directory)" | \
      "error connecting to "*"(Connection refused)") exit 2 ;;
  esac
  printf '%s: %s\n' "${tmux[*]}" "$out"
  exit 3
}

now=${EPOCHSECONDS:-$(date +%s)} # a builtin from bash 5 on; 3.2 forks date
watched=1
evidence=''
{
  IFS='|' read -r sid win idx zoomed name
  [ -n "$sid" ] || exit 2
  if [ "$what" = session-name ]; then
    printf '%s\n' "$name"
    exit 0
  fi

  while IFS='|' read -r csid cwin cidx activity client flags; do
    [ -n "$client" ] || continue

    # In scope for the evidence: the clients of the target's session, and
    # for a pane any other that shows its window (one linked into two
    # sessions).
    if [ "$csid" != "$sid" ]; then
      [ "$what" = pane ] && [ "$cwin" = "$win" ] || continue
    fi

    age=$((now - activity))
    case ",$flags," in
      *,focused,*) state=focused ;;
      *) state="not focused" ;;
    esac

    # A pane is seen by a client that shows it; a session by any of its own.
    unseen=''
    if [ "$what" = pane ]; then
      if [ "$cwin" != "$win" ]; then
        unseen=", on window $cidx (the pane's is $idx)"
      elif [ -n "$zoomed" ]; then
        unseen=", the pane's window zoomed onto another pane"
      fi
    fi

    if [ -z "$unseen" ] && [ "$state" = focused ] && [ "$age" -lt "$STALE" ]; then watched=0; fi
    evidence="${evidence:+$evidence; }${client#/dev/} $state, input ${age}s ago$unseen"
  done
} <<ANSWER
$out
ANSWER

printf '%s\n' "${evidence:-no client attached}"
exit "$watched"

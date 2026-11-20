#!/usr/bin/env bash
# tmux_watched.sh -- is somebody looking? The one rule for "a tmux client
# counts as a person who is there", and the two questions asked with it:
#
#   tmux_watched.sh pane <socket> <pane id>
#       is this pane on somebody's screen?   asked by the session-done mod,
#       for its ntfy push (home/.claude/mods/session-done/hooks/push.ts)
#   tmux_watched.sh session <socket> <session id>
#       is anybody on this session, at any of its windows?   asked by
#       home/.config/tmux/bell-elsewhere.sh, for the bell marker on the bars
#   tmux_watched.sh session-name <socket> <pane id>
#       the name of the session the pane is in now, for the push's title
#
#   exit 0  watched; for session-name, the name on stdout
#        1  not watched
#        2  gone: the server, the pane or the session
#        3  tmux failed otherwise; stdout: "tmux -S <socket>: <its message>"
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
#   - It is a terminal. A control-mode client (tmux -C: the history tracker,
#     scripts/tmux_history.py) has nobody behind it, yet counts as attached
#     and reports itself focused. Known limit: iTerm2's tmux integration
#     (tmux -CC) is a control-mode client with a person behind it, who never
#     counts here; nobody on these machines uses it.
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
# Two tmux calls a question: where the target is, then every client of the
# server, judged here. Runs on stock macOS too (bash 3.2, which run-shell
# finds on the server's PATH): builtins and tmux alone.
set -u

STALE=${TMUX_WATCHED_STALE_SECONDS:-1800}

usage() {
  echo "tmux_watched.sh: usage: tmux_watched.sh pane <socket> <pane id> | session <socket> <session id> | session-name <socket> <pane id>" >&2
  exit 64
}

case "${1:-} $#" in
  "pane 3" | "session 3" | "session-name 3") ;;
  *) usage ;;
esac
what=$1 socket=$2 target=$3

# ask <tmux args...>: run tmux on the socket, its output in $out. On a
# failure this script ends: with 2 if the server is gone (the messages tmux
# prints when nothing listens on the socket), with 3 and tmux's message on
# any other, a client too old for the server, say. That one must not read as
# "gone": a caller told so drops what it had to say without a word.
ask() {
  out=$(tmux -S "$socket" "$@" 2>&1) && return 0
  case $out in
    "no server running on "* | "error connecting to "*"(No such file or directory)" | \
      "error connecting to "*"(Connection refused)") exit 2 ;;
  esac
  printf 'tmux -S %s: %s\n' "$socket" "$out"
  exit 3
}

# Where the target is now. display-message does not fail on a target that is
# gone, it expands every format to nothing (tmux 3.8):
#   pane %4     -> "$3|@1|0|solo|"   or "...|zoomed" while its window shows
#                  another of its panes
#   session $3  -> "$3|@2|1|solo|"   its current window, which is not asked
#   gone        -> "||||"
ask display-message -p -t "$target" \
  '#{session_id}|#{window_id}|#{window_index}|#{session_name}|#{?#{&&:#{window_zoomed_flag},#{!=:#{pane_active},1}},zoomed,}'
IFS='|' read -r sid win idx name zoomed <<WHERE
$out
WHERE
[ -n "$sid" ] || exit 2

if [ "$what" = session-name ]; then
  printf '%s\n' "$name"
  exit 0
fi

# Every client of the server, one a line; a server with none prints nothing:
#   "0|$3|@2|1|1795149619|/dev/ttys001|attached,focused,UTF-8"
ask list-clients -F \
  '#{client_control_mode}|#{session_id}|#{window_id}|#{window_index}|#{client_activity}|#{client_name}|#{client_flags}'
now=${EPOCHSECONDS:-$(date +%s)} # a builtin from bash 5 on; 3.2 forks date

watched=1
evidence=''
while IFS='|' read -r control csid cwin cidx activity client flags; do
  [ -n "$client" ] || continue # no clients: the listing is one empty line
  [ "$control" = 1 ] && continue

  # In scope for the evidence: the clients of the target's session, and for
  # a pane any other that shows its window (one linked into two sessions).
  if [ "$csid" != "$sid" ]; then
    [ "$what" = pane ] && [ "$cwin" = "$win" ] || continue
  fi

  age=$((now - activity))
  case ",$flags," in
    *,focused,*) state=focused ;;
    *) state="not focused" ;;
  esac
  line="${client#/dev/} $state, input ${age}s ago"

  # A pane is seen by a client that shows it; a session by any of its own.
  sees=1
  if [ "$what" = pane ]; then
    if [ "$cwin" != "$win" ]; then
      sees=''
      line="$line, on window $cidx (the pane's is $idx)"
    elif [ -n "$zoomed" ]; then
      sees=''
      line="$line, the pane's window zoomed onto another pane"
    fi
  fi

  if [ -n "$sees" ] && [ "$state" = focused ] && [ "$age" -lt "$STALE" ]; then watched=0; fi
  evidence="${evidence:+$evidence; }$line"
done <<CLIENTS
$out
CLIENTS

printf '%s\n' "${evidence:-no client attached}"
exit "$watched"

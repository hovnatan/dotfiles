#!/usr/bin/env bash
# Synthesize the focus-out an abruptly killed tmux client never sent.
#
# Claude Code enables terminal focus reporting and suppresses its mobile
# push while the terminal claims focus ("user present"). tmux delivers a
# real focus-out on a graceful detach (prefix d), but a client that dies
# abruptly -- a closed VS Code tab, a dropped SSH -- just vanishes: the
# pane keeps its last "focused" state, so every later push is dropped
# while the local bell still rings. Invoked from the client-detached and
# client-session-changed hooks with #{socket_path}, and as a Claude Code
# SessionStart hook with no argument -- there the socket is the first
# field of $TMUX, and outside tmux there is nothing to sweep. Writes
# ESC [ O (the focus-out sequence, hex 1b 5b 4f) into every Claude Code
# pane of every session no client is attached to. Repeats are harmless,
# and attaching again delivers a real focus-in.
set -u

socket="${1:-}"
if [ -z "$socket" ]; then
  t=${TMUX:-}
  socket=${t%%,*}
  [ -n "$socket" ] || exit 0
fi

tmux -S "$socket" list-panes -a \
    -F '#{session_attached}	#{pane_current_command}	#{pane_id}' 2>/dev/null |
while IFS=$'\t' read -r attached cmd pane_id; do
    [ "$attached" = 0 ] && [ "$cmd" = claude ] || continue
    tmux -S "$socket" send-keys -t "$pane_id" -H 1b 5b 4f 2>/dev/null || true
done
exit 0

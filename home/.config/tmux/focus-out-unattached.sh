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

# Which panes run Claude Code? Not #{pane_current_command}: the installed
# binary is version-named (~/.local/bin/claude -> .../versions/2.1.246) and
# macOS tmux reports the resolved symlink target, so that field reads
# "2.1.246" and changes on every update -- the old `= claude` test silently
# matched nothing and the whole sweep no-oped. argv[0] is still "claude", and
# `-o args=` is the one ps field that means argv[0] on both macOS and Linux
# (`comm` is argv[0] on macOS but the kernel task name on Linux).
#
# Only the foreground process group counts: send-keys writes into the tty, so
# for a suspended claude (no "+" in STAT) the escape would land on the shell
# prompt instead. argv[0] carries a path when claude is launched by path (the
# VS Code extension does), hence the basename match rather than a compare.
tmux -S "$socket" list-panes -a -f '#{==:#{session_attached},0}' \
    -F '#{pane_tty}	#{pane_id}' 2>/dev/null |
while IFS=$'\t' read -r tty pane_id; do
    ps -t "$tty" -o stat=,args= 2>/dev/null |
        awk '$1 ~ /\+/ && $2 ~ /(^|\/)claude$/ { f = 1; exit }
             END { exit !f }' || continue
    tmux -S "$socket" send-keys -t "$pane_id" -H 1b 5b 4f 2>/dev/null || true
done
exit 0

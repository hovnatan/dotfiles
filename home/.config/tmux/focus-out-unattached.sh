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

# Which panes run Claude Code is tmux.conf's @claude_pane, true for a pane
# with claude in the foreground. A suspended claude is not one: send-keys
# writes into the tty, so the escape would land on the shell's prompt. Without
# the option the sweep would match nothing and say nothing.
#
# What was sent is logged with the other tmux hooks, one line per sweep that
# sent anything: this is the other half of "why was I not notified", the
# focus Claude Code itself believes in.
#   2026-09-30T14:07:07Z synthetic focus-out to %0 (claude) %2 (backend): no client attached
[ -n "$(tmux -S "$socket" show-options -gqv @claude_pane)" ] || {
  echo "focus-out-unattached.sh: @claude_pane is not set on the tmux server at $socket: load home/.config/tmux/tmux.conf there" >&2
  exit 1
}
sent=
while IFS=$'\t' read -r pane_id session; do
  tmux -S "$socket" send-keys -t "$pane_id" -H 1b 5b 4f 2>/dev/null || continue
  sent="$sent $pane_id ($session)"
done < <(tmux -S "$socket" list-panes -a \
  -f '#{&&:#{==:#{session_attached},0},#{E:@claude_pane}}' \
  -F '#{pane_id}	#{session_name}' 2>/dev/null)
if [ -n "$sent" ]; then
  # shellcheck source=scripts/lib/event_log.sh
  . "${0%/*}/../../../scripts/lib/event_log.sh"
  event_log_note tmux_hooks "synthetic focus-out to${sent}: no client attached"
fi
exit 0

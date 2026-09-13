#!/usr/bin/env bash
# Label the Claude Code conversation running in this tmux pane with its task:
#
#   label-session.sh <task>   -->  types "/rename <hostname>-<name>/<task>"
#                                  into the pane, Enter included
#
# <name> is the tmux session's bare name (its label, if any, dropped), so
# from session "backend" or "backend/old-task" the title becomes
# "vm-backend/<task>" -- the convention claude_tmux_run.sh resolves
# (Naming there), which the pane-title-changed hook then mirrors back onto
# the tmux session as "backend/<task>".
#
# Why typing. Nothing outside a live session can rename it: no hook output,
# flag or tool does, only /rename typed at its prompt (see session-clear.sh,
# which types for the same reason). Typed while a turn runs -- the /label
# skill's own -- the command queues and runs when the turn ends (checked on
# 2.1.270: the label shows in the prompt bar right after the reply).
#
# The /label skill beside this file is its only caller. Prints the title it
# typed; every refusal is an error with the reason, never a silent no-op,
# since the user is waiting to see the label appear.
set -u

task=${1:-}
[ -n "$task" ] || { echo "label-session.sh: no task given (usage: label-session.sh <task>)" >&2; exit 2; }
# The alphabet NAME_RE in claude_tmux_run.sh accepts for a task: what tmux
# keeps verbatim (it rewrites "." and ":" to "_"), and no "/" -- one label,
# not a path.
case "$task" in
  *[!A-Za-z0-9_-]*) echo "label-session.sh: task '$task' may only use letters, digits, '-' and '_'" >&2; exit 2 ;;
esac

[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || { echo "label-session.sh: not inside a tmux pane" >&2; exit 1; }
socket=${TMUX%%,*}
# Only the claude socket (or the one a test names): its sessions are the
# ones named "<hostname>-<name>"; elsewhere the convention does not hold.
[ "${socket##*/}" = "${CLAUDE_TMUX_SOCKET:-claude}" ] ||
  { echo "label-session.sh: pane is on tmux socket '${socket##*/}', not the claude socket" >&2; exit 1; }

# Type only into a claude that holds its terminal's foreground group: a
# nested `claude -p` run from a session's Bash tool inherits TMUX_PANE but
# has no tty, and typing on its behalf would land in the parent's pane.
if [ -z "${CLAUDE_PID:-}" ]; then
  echo "label-session.sh: CLAUDE_PID missing; run this from a Claude Code session's Bash tool" >&2; exit 1
fi
read -r pgid tpgid < <(ps -o pgid=,tpgid= -p "$CLAUDE_PID" 2>/dev/null)
[ -n "${pgid:-}" ] && [ "$pgid" = "${tpgid:-}" ] ||
  { echo "label-session.sh: claude $CLAUDE_PID is not the pane's foreground process (nested session?)" >&2; exit 1; }

session=$(tmux -S "$socket" display-message -p -t "$TMUX_PANE" '#{session_name}')
title="$(hostname)-${session%%/*}/$task"
tmux -S "$socket" send-keys -t "$TMUX_PANE" -l "/rename $title" \; send-keys -t "$TMUX_PANE" Enter
echo "$title"

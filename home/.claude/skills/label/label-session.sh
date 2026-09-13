#!/usr/bin/env bash
# Label the Claude Code conversation running in a tmux pane with its task:
#
#   label-session.sh <task>                        from the /label skill, in
#                                                  the session's own Bash tool
#   label-session.sh --pane <socket> <pane> <task> from the tmux "prefix L"
#                                                  binding in ~/.tmux.conf
#
# Either way it types "/rename <hostname>-<name>/<task>" into the pane, Enter
# included. The skill form costs a model turn and checks it is not typing on
# behalf of a nested claude; the pane form costs nothing, works while Claude
# is busy (the command queues), and instead checks that the pane's
# foreground process is claude, reporting through tmux's message line.
#
# <name> is the tmux session's bare name (its label, if any, dropped), so
# from session "backend" or "backend/old-task" the title becomes
# "hov-8cpu-backend/<task>" -- the convention claude_tmux_run.sh resolves
# (Naming there), which the pane-title-changed hook then mirrors back onto
# the tmux session as "backend/<task>".
#
# Why typing. Nothing outside a live session can rename it: no hook output,
# flag or tool does, only /rename typed at its prompt (see session-clear.sh,
# which types for the same reason). Typed while a turn runs -- the /label
# skill's own -- the command queues and runs when the turn ends (checked on
# 2.1.270: the label shows in the prompt bar right after the reply).
#
# The /label skill beside this file and the tmux binding are its only
# callers. Prints the title it typed; every refusal is an error with the
# reason, never a silent no-op, since the user is waiting to see the label
# appear.
set -u

# In pane mode a refusal must reach the user through tmux, since run-shell
# has no terminal of its own; the skill relays stderr itself.
mode=skill
if [ "${1:-}" = --pane ]; then
  mode=pane
  socket=${2:-} pane=${3:-} task=${4:-}
  [ -n "$socket" ] && [ -n "$pane" ] ||
    { echo "label-session.sh: usage: label-session.sh --pane <socket> <pane> <task>" >&2; exit 2; }
  fail() { tmux -S "$socket" display-message -t "$pane" "label: $1"; echo "label-session.sh: $1" >&2; exit "${2:-1}"; }
else
  task=${1:-}
  fail() { echo "label-session.sh: $1" >&2; exit "${2:-1}"; }
fi
[ -n "$task" ] || fail "no task given" 2
# The alphabet NAME_RE in claude_tmux_run.sh accepts for a task: what tmux
# keeps verbatim (it rewrites "." and ":" to "_"), and no "/" -- one label,
# not a path.
case "$task" in
  *[!A-Za-z0-9_-]*) fail "task '$task' may only use letters, digits, '-' and '_'" 2 ;;
esac

if [ "$mode" = skill ]; then
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || fail "not inside a tmux pane"
  socket=${TMUX%%,*} pane=$TMUX_PANE
fi
# Only the claude socket (or the one a test names): its sessions are the
# ones named "<hostname>-<name>"; elsewhere the convention does not hold.
[ "${socket##*/}" = "${CLAUDE_TMUX_SOCKET:-claude}" ] ||
  fail "pane is on tmux socket '${socket##*/}', not the claude socket"

if [ "$mode" = skill ]; then
  # Type only into a claude that holds its terminal's foreground group: a
  # nested `claude -p` run from a session's Bash tool inherits TMUX_PANE
  # but has no tty, and typing on its behalf would land in the parent's pane.
  [ -n "${CLAUDE_PID:-}" ] || fail "CLAUDE_PID missing; run this from a Claude Code session's Bash tool"
  read -r pgid tpgid < <(ps -o pgid=,tpgid= -p "$CLAUDE_PID" 2>/dev/null)
  [ -n "${pgid:-}" ] && [ "$pgid" = "${tpgid:-}" ] ||
    fail "claude $CLAUDE_PID is not the pane's foreground process (nested session?)"
else
  # From the binding the pane is whatever the user is looking at; only a
  # claude prompt can take a /rename.
  cmd=$(tmux -S "$socket" display-message -p -t "$pane" '#{pane_current_command}')
  [ "$cmd" = claude ] || fail "pane $pane is running '$cmd', not claude"
fi

session=$(tmux -S "$socket" display-message -p -t "$pane" '#{session_name}')
title="$(hostname)-${session%%/*}/$task"
tmux -S "$socket" send-keys -t "$pane" -l "/rename $title" \; send-keys -t "$pane" Enter
[ "$mode" = pane ] && tmux -S "$socket" display-message -t "$pane" "label: $title"
echo "$title"

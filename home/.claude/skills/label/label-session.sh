#!/usr/bin/env bash
# Label the Claude Code conversation running in a tmux pane with its task:
#
#   label-session.sh <task> [<socket> <pane>]
#
# types "/rename <hostname>-<name>/<task>" into the pane, Enter included.
# The socket and pane default to this process's own ($TMUX, $TMUX_PANE),
# which is how the /label skill beside this file calls it from the
# session's Bash tool; the "prefix L" binding in ~/.tmux.conf passes the
# pane the user is looking at. <name> is the tmux session's bare name (its
# label, if any, dropped), so from session "backend" or "backend/old-task"
# the title becomes "hov-8cpu-backend/<task>" -- the convention
# claude_tmux_run.sh resolves (Naming there), which the pane-title-changed
# hook then mirrors back onto the tmux session as "backend/<task>".
#
# Why typing. Nothing outside a live session can rename it: no hook output,
# flag or tool does, only /rename typed at its prompt (see session-clear.sh,
# which types for the same reason). Typed while a turn runs -- the /label
# skill's own, or whatever the pane is busy with under prefix L -- the
# command queues and runs when the turn ends (checked on 2.1.270: the label
# shows in the prompt bar right after the reply).
#
# The one check: the pane's tty must have a claude in its foreground process
# group, the probe focus-out-unattached.sh settled on (#{pane_current_command}
# reads the version-named binary on macOS tmux, so it is not that). Run
# from inside a session, CLAUDE_PID is set and must BE that claude: a nested
# `claude -p` started from a session's Bash tool inherits TMUX_PANE, and
# typing on its behalf would label the parent's conversation.
#
# Reports on tmux's message line as well as stdout/stderr -- the binding has
# no terminal of its own, and in a session the user is looking at that pane
# anyway. Every refusal names its reason: the user is waiting for the label.
set -u

task=${1:-}
own=${TMUX:-}
socket=${2:-${own%%,*}}
pane=${3:-${TMUX_PANE:-}}

notify() { [ -n "$socket" ] && [ -n "$pane" ] && tmux -S "$socket" display-message -t "$pane" "label: $1" 2>/dev/null; }
fail() { notify "$1"; echo "label-session.sh: $1" >&2; exit "${2:-1}"; }

[ -n "$task" ] || fail "usage: label-session.sh <task> [<socket> <pane>]" 2
# The alphabet NAME_RE in claude_tmux_run.sh accepts for a task: what tmux
# keeps verbatim (it rewrites "." and ":" to "_"), and no "/" -- one label,
# not a path.
case "$task" in
  *[!A-Za-z0-9_-]*) fail "task '$task' may only use letters, digits, '-' and '_'" 2 ;;
esac
[ -n "$socket" ] && [ -n "$pane" ] || fail "not inside a tmux pane, and no socket and pane given"
# Only the claude socket (or the one a test names): its sessions are the
# ones named "<hostname>-<name>"; elsewhere the convention does not hold.
[ "${socket##*/}" = "${CLAUDE_TMUX_SOCKET:-claude}" ] ||
  fail "pane is on tmux socket '${socket##*/}', not the claude socket"

read -r tty session < <(tmux -S "$socket" display-message -p -t "$pane" '#{pane_tty} #{session_name}' 2>/dev/null)
[ -n "${tty:-}" ] || fail "no pane $pane on socket ${socket##*/}"
# `-o args=` is argv[0] on both macOS and Linux; the basename match covers a
# claude launched by path (the VS Code extension does); "+" in STAT is the
# foreground process group, where send-keys lands.
claude_pid=$(ps -t "$tty" -o stat=,pid=,args= 2>/dev/null |
  awk '$1 ~ /\+/ && $3 ~ /(^|\/)claude$/ { print $2; exit }')
[ -n "$claude_pid" ] || fail "no claude in the foreground of pane $pane"
[ -z "${CLAUDE_PID:-}" ] || [ "$CLAUDE_PID" = "$claude_pid" ] ||
  fail "claude $CLAUDE_PID is not the pane's foreground claude (nested session?)"

title="$(hostname)-${session%%/*}/$task"
tmux -S "$socket" send-keys -t "$pane" -l "/rename $title" \; send-keys -t "$pane" Enter
notify "$title"
echo "$title"

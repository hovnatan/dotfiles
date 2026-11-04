#!/usr/bin/env bash
# claude-tmux.service's ExecStart: open the "manager" tmux session, with claude
# typed into window 0's plain shell. A session already there is left alone,
# whatever runs in it.
#
#   session "manager" up   -> nothing
#   none                   -> window 0: a new conversation; an earlier one stays
#                             on disk, for a resume by hand
#                             window "remote-control": `claude remote-control`,
#                             on a machine that names a folder for it
#
# Typed, not exec'd: claude quitting leaves the shell, and the session with it.
# The rest of a session's setup (Remote Control, the agent view off) is
# home/.claude/settings.json.
set -euo pipefail

session=manager
dir="$HOME/.dotfiles/claude_tmux_session"
# Machine-local, one line, an absolute path: the folder this machine's Remote
# Control server runs from. No file, no window; a file naming no folder stops
# the start below, before anything opens, so fixing it and starting again works.
rc_file="$HOME/.config/claude-tmux/remote-control-dir"

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/lib/event_log.sh"
# --no-prune: the manager's start must not fail with a prune; the day's falls to
# the next script that starts a log with one.
event_log_start claude_manager_start --no-prune

if tmux has-session -t "=$session" 2>/dev/null; then
  log "session $session is up; leaving it"
  exit 0
fi

rc_dir=""
if [ -e "$rc_file" ]; then
  rc_dir=$(<"$rc_file")
  [[ "$rc_dir" == /* ]] && [ -d "$rc_dir" ] || {
    log "FAILED: $rc_file holds '$rc_dir', not the absolute path of a folder; fix or remove it, then start again"
    exit 1
  }
fi

# In a scope of its own, or a server started here would be in the service's
# cgroup, and `systemctl --user stop|restart claude-tmux` would take every
# session with it. tmux >= 3.7 marks each pane's scope PartOf= its server's unit:
#
#   claude-tmux.service   oneshot: this script ran and returned, no process
#   run-<random>.scope    tmux server  <--PartOf--  tmux-spawn-*.scope (a pane each)
#
# A random name, so nothing a dead server left can refuse the next one. With a
# server already up, this only runs the client in a scope that ends with it.
systemd-run --user --scope --quiet --collect tmux new-session -d -s "$session" -c "$dir"

# Typed at once, before the shell has drawn a prompt: the terminal holds the keys.
tmux send-keys -t "=$session:0" -l -- "claude -n $(hostname)/$session --dangerously-skip-permissions"
tmux send-keys -t "=$session:0" Enter
log "session $session opened in $dir, claude typed"

# Typed like window 0, so the server stopping leaves a shell to start it from.
# Its window id, not its name: a target that cannot go stale. --spawn: in a git
# repo the server otherwise asks for a mode, in a window nobody is watching.
[ -n "$rc_dir" ] || exit 0
window=$(tmux new-window -d -P -F '#{window_id}' -t "=$session:" -n remote-control -c "$rc_dir")
tmux send-keys -t "$window" -l -- "claude remote-control --spawn=same-dir --name $(hostname)/remote-control"
tmux send-keys -t "$window" Enter
log "window remote-control opened in $rc_dir, claude remote-control typed"

#!/usr/bin/env bash
# tmux pane-title-changed hook (declared in ~/.tmux.conf): keep a tmux
# session named after the Claude Code conversation it hosts, so `tmux ls`,
# the session switcher and the status bar show the conversation's task
# label (see Naming in ~/.dotfiles/scripts/claude_tmux_run.sh, which
# creates sessions under the bare name and leaves the label to this hook).
#
# Claude Code sets its pane title to "<glyph> <session name>" and updates
# it live on /rename; tmux announces every change of it. This strips
# everything up to the "<hostname>-" prefix and renames the session when
# the rest differs:
#
#   pane title "* hov-8cpu-backend/asyncssh-advisory"
#     --> tmux session "backend/asyncssh-advisory"
#   pane title "* hov-8cpu-backend"      (after /clear, or an unlabeled one)
#     --> tmux session "backend"
#
#   args: socket_path session_id session_name pane_title
#
# Titles without the prefix -- a shell, an editor, a claude started without
# the convention's -n -- change nothing, on any server. One that carries it
# renames its session wherever it runs, which is the convention doing its
# job. tmux canonicalises names itself ("." and ":" become "_"), so a label
# outside the launcher's alphabet still lands, spelled tmux's way; and a
# name another session holds fails aloud (tmux prints the error into the
# pane): two sessions hosting conversations of one name is a conflict
# worth seeing, not hiding.
set -u
socket=$1 sid=$2 sname=$3 title=$4

want=${title#*" $HOSTNAME-"}
[ "$want" != "$title" ] && [ "$want" != "$sname" ] || exit 0
exec tmux -S "$socket" rename-session -t "$sid" "$want"

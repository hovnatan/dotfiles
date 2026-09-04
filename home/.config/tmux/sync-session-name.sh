#!/usr/bin/env bash
# tmux pane-title-changed hook (declared in ~/.tmux.conf): on the claude
# socket, keep a tmux session named after the Claude Code conversation it
# hosts, minus the hostname, so `tmux ls`, the session switcher and the
# status bar show the conversation's task label (see Naming in
# ~/.dotfiles/scripts/claude_tmux_run.sh, which creates sessions under the
# bare name and leaves the label to this hook).
#
# Claude Code sets its pane title to "<glyph> <session name>" and updates
# it live on /rename; tmux announces every change of it. This takes the
# name after the glyph, drops the "<hostname>-" prefix, and renames the
# session when the rest differs:
#
#   pane title "* hov-8cpu-backend/asyncssh-advisory"  -->  session "backend/asyncssh-advisory"
#   pane title "* hov-8cpu-backend"    (after /clear)   -->  session "backend"
#
#   args: socket_path session_id session_name pane_title
#
# Only that socket (or the one a test names): its sessions are the ones
# the script names, while a claude started by hand elsewhere would rename
# whatever session it sits in. Only a "<glyph> <hostname>-<one word>"
# title: a shell or editor pane ("zsh", "vim file") has no glyph, and an
# unnamed claude ("* Claude Code") neither the prefix nor one word. The
# glyph is recognised as "no ASCII letter or digit", not by its code
# point, so this holds in any locale. tmux canonicalises names itself
# ("." and ":" become "_"), and a name another session holds fails aloud
# (tmux prints the error into the pane): two sessions hosting
# conversations of one name is a conflict worth seeing, not hiding.
set -u
socket=$1 sid=$2 sname=$3 title=$4

[ "${socket##*/}" = "${CLAUDE_TMUX_SOCKET:-claude}" ] || exit 0
glyph=${title%% *} want=${title#* }
[ "$glyph" != "$title" ] || exit 0
case "$glyph" in *[A-Za-z0-9]*) exit 0 ;; esac
case "$want" in "$HOSTNAME-"*) want=${want#"$HOSTNAME-"} ;; *) exit 0 ;; esac
case "$want" in *" "*) exit 0 ;; esac
[ "$want" != "$sname" ] || exit 0
exec tmux -S "$socket" rename-session -t "$sid" "$want"

#!/bin/sh
# tmux client-attached / client-session-changed hook (declared in
# ~/.tmux.conf): report each attach to the client's terminal. The tab names
# this machine while the last attach came in over ssh, as the shells' titles
# do over ssh:
#
#   ssh <host>, tmux attach, iTerm2  --> host_tag     --> "(<host>) [cl]"
#   ssh <host>, tmux attach, other   --> @ssh=1       --> "(<host>) [cl]"
#   local tmux attach, iTerm2        --> host_tag     --> "(<local>) [cl]"
#   local tmux attach, other         --> @ssh unset   --> "[cl]"
#
# iTerm2 clients also get in_tmux=1 (iterm2_report_host.fish explains it).
# client-session-changed matters for that: it is the only one of the two
# hooks that `tmux new-session` fires.
#
# Formats cannot read the environment, so the session environment carries
# it: tmux's update-environment copies the attaching client's SSH_CONNECTION,
# LC_TERMINAL and TERM_PROGRAM into it, or marks them removed
# ("-SSH_CONNECTION") when the client has none.
#
# iTerm2 (same test as home/.config/fish/functions/is_iterm2.fish) prepends
# the host itself from the reports iterm2_report_host.fish explains and
# writes, but a program in a pane cannot reach it through tmux, and
# `ssh -t <host> tmux attach` runs no prompt that would, so the hook has the
# same function write them straight to the client's tty.
#
# Other terminals get @ssh, which set-titles-string reads. The client is then
# redrawn: tmux re-sends the title only on a redraw, and the attach redrew
# before this hook ran, so a local attach after an ssh one would otherwise
# keep the stale "(<host>) ". One flag per session, so a local and an ssh
# client on the same session both show the title of the last attach.
#
#   args: socket_path session_id client_name client_tty
set -eu
sock=$1 session=$2 client=$3 tty=$4

# The attaching client's variables; removed ones ("-NAME") match nothing and
# stay empty.
ssh='' lc_terminal='' term_program=''
while IFS= read -r line; do
  case $line in
    SSH_CONNECTION=*) ssh=${line#*=} ;;
    LC_TERMINAL=*) lc_terminal=${line#*=} ;;
    TERM_PROGRAM=*) term_program=${line#*=} ;;
  esac
done <<EOF
$(tmux -S "$sock" show-environment -t "$session")
EOF

iterm2=
case $lc_terminal:$term_program in iTerm2: | iTerm2:iTerm.app) iterm2=1 ;; esac

# The reports the prompt sends, from the same fish function so tab and
# prompt agree, with in_tmux 1. This process's environment is the tmux
# server's, so the client's ssh state goes in as the flag.
if [ -n "$iterm2" ]; then
  where=local
  [ -n "$ssh" ] && where=ssh
  fish -c "iterm2_report_host --tmux-attach=$where" >"$tty"
fi

if [ -n "$ssh" ] && [ -z "$iterm2" ]; then
  tmux -S "$sock" set -t "$session" @ssh 1 \; refresh-client -t "$client"
else
  tmux -S "$sock" set -t "$session" -u @ssh \; refresh-client -t "$client"
fi

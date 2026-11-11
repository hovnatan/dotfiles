#!/usr/bin/env bash
# tmux client-attached / client-session-changed hook (declared in
# ~/.config/tmux/tmux.conf): the client's terminal title names where the last
# attach came from, as the shells' titles do: this machine over ssh, "local"
# otherwise.
#
#   ssh <host>, tmux attach  --> @title_host=<host>  --> "(<host>) [backend]"
#   local tmux attach        --> @title_host=local   --> "(local) [backend]"
#
# client-session-changed is the only one of the two hooks that
# `tmux new-session` fires, so `ssh -t <host> tmux new` gets its title too.
#
# Formats cannot read the environment, so the session environment carries
# it: tmux's update-environment copies the attaching client's SSH_CONNECTION
# into it, or marks it removed ("-SSH_CONNECTION") when the client has none.
#
# set-titles-string reads @title_host. The client is then redrawn: tmux
# re-sends the title only on a redraw, and the attach redrew before this hook
# ran, so a local attach after an ssh one would otherwise keep the stale
# "(<host>) ". One value per session, so a local and an ssh client on the
# same session both show the title of the last attach.
#
# What was set, and for whom, is logged with the other tmux hooks
# (log-event.sh says where and why):
#   2026-11-10T13:01:58Z attached /dev/pts/1 session=proj: over ssh: @title_host vm
#   2026-11-10T14:07:07Z session-changed /dev/pts/3 session=bench: local: @title_host local
#
#   args: socket_path session_id client_name client_tty event
#         (event: attached | session-changed, for the log)
set -eu
sock=$1 session=$2 client=$3 tty=$4 event=$5
# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"
name=$(tmux -S "$sock" display-message -p -t "$session" '#{session_name}')
note() { event_log_note tmux_hooks "$event $tty session=$name: $*"; }

# The attaching client's SSH_CONNECTION; a removed one ("-SSH_CONNECTION")
# matches nothing and stays empty.
ssh=''
while IFS= read -r line; do
  case $line in
    SSH_CONNECTION=*) ssh=${line#*=} ;;
  esac
done <<EOF
$(tmux -S "$sock" show-environment -t "$session")
EOF

# The label the title leads with: tmux's own short host name over ssh (the
# one the bar has always shown), "local" otherwise.
where=local label=local
if [ -n "$ssh" ]; then
  where="over ssh"
  label=$(tmux -S "$sock" display-message -p '#{host_short}')
fi
tmux -S "$sock" set -t "$session" @title_host "$label" \; refresh-client -t "$client"
note "$where: @title_host $label"

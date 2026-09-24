#!/bin/sh
# tmux client-attached / client-session-changed hook (declared in
# ~/.tmux.conf): flag a session @ssh while its last attach came in over ssh,
# so set-titles-string can lead with this machine's name in the terminal
# tab, as the shells' titles do over ssh:
#
#   ssh <host>, tmux attach   -->  @ssh=1   -->  title "(<host>) [cl]"
#   local tmux attach         -->  @ssh unset  -->  title "[cl]"
#
# Formats cannot read the environment, so the flag carries it: tmux's
# update-environment copies the attaching client's SSH_CONNECTION into the
# session environment, or marks it removed ("-SSH_CONNECTION") when the
# client has none. The client is then redrawn, since tmux re-sends the
# title only on a redraw and the attach redrew before this hook ran: a
# local attach after an ssh one would otherwise keep the stale "(<host>) ".
# One flag per session, so a local and an ssh client on the same session
# both show the title of the last attach.
#
#   args: socket_path session_id client_name
set -eu
sock=$1 session=$2 client=$3

if tmux -S "$sock" show-environment -t "$session" SSH_CONNECTION 2>/dev/null | grep -q '^SSH_CONNECTION='; then
  tmux -S "$sock" set -t "$session" @ssh 1
else
  tmux -S "$sock" set -t "$session" -u @ssh
fi
tmux -S "$sock" refresh-client -t "$client"

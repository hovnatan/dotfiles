#!/usr/bin/env bash
# tmux client-attached / client-session-changed hook (declared in
# ~/.tmux.conf): report each attach to the client's terminal. The tab names
# this machine while the last attach came in over ssh, as the shells' titles
# do over ssh:
#
#   ssh <host>, tmux attach, iTerm2  --> host_tag     --> "(<host>) [backend]"
#   ssh <host>, tmux attach, other   --> @ssh=1       --> "(<host>) [backend]"
#   local tmux attach, iTerm2        --> host_tag     --> "(<local>) [backend]"
#   local tmux attach, other         --> @ssh unset   --> "[backend]"
#
# client-session-changed is the only one of the two hooks that
# `tmux new-session` fires, so `ssh -t <host> tmux new` gets its report too.
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
# What was reported, and to whom, is logged with the other tmux hooks
# (log-event.sh says where and why): the host report is one of the things
# iTerm2 judges a change of host by, and a report that cannot be written
# (the pty of a Tailscale SSH session that runs a command stays root's)
# fails here, with the line to show for it.
#   2026-09-30T13:01:58Z attached /dev/pts/1 session=summit: iTerm2 over ssh, reported azureuser@vm
#   2026-09-30T14:07:07Z session-changed /dev/pts/1 session=bench: iTerm2 over ssh, reported azureuser@vm
#   2026-09-30T00:44:24Z attached /dev/pts/7 session=t: iTerm2 over ssh, FAILED: cannot write to /dev/pts/7
#
#   args: socket_path session_id client_name client_tty event
#         (event: attached | session-changed, for the log)
set -eu
sock=$1 session=$2 client=$3 tty=$4 event=$5
# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"
name=$(tmux -S "$sock" display-message -p -t "$session" '#{session_name}')
note() { event_log_note tmux_hooks "$event $tty session=$name: $*"; }

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
# prompt agree. This process's environment is the tmux server's, so the
# client's ssh state goes in as the flag.
where=local
[ -n "$ssh" ] && where="over ssh"
if [ -n "$iterm2" ]; then
  report=$(fish -c "iterm2_report_host --tmux-attach=${where#over }")
  host=${report#*RemoteHost=}
  host=${host%%$'\a'*}
  if ! printf '%s' "$report" >"$tty"; then
    note "iTerm2 $where, FAILED: cannot write to $tty"
    exit 1
  fi
  note "iTerm2 $where, reported $host"
fi

if [ -n "$ssh" ] && [ -z "$iterm2" ]; then
  tmux -S "$sock" set -t "$session" @ssh 1 \; refresh-client -t "$client"
  note "not iTerm2, over ssh: @ssh set"
else
  tmux -S "$sock" set -t "$session" -u @ssh \; refresh-client -t "$client"
  [ -n "$iterm2" ] || note "not iTerm2, local: @ssh unset"
fi

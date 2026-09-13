#!/bin/sh
# Make tmux re-send the terminal title to every client on this server.
#
# Why. VS Code keeps a terminal's shell and tmux client alive across a window
# reload (persistent sessions) and only replays the tail of its output to the
# rebuilt window, so the title tmux wrote once at attach time is gone, and
# tmux never writes it again: it compares each client's new title against the
# one it last sent and only writes on a change. The rebuilt tab therefore
# reads "zsh" (the launch executable) until the foreground process changes.
#
# How. tmux formats set-titles-string per client and writes the result when
# it differs from the last write, so nudging the string between two
# renderings that display the same -- "[cl]" and "[cl] " -- forces one write
# to every client on the socket, whichever session's Claude ran this:
#
#   set-titles-string "[#{=2:session_name}]"   -> client title "[cl]"
#   set-titles-string "[#{=2:session_name}] "  -> client title "[cl] "
#
# Called from the Claude Code statusLine command in ~/.claude/settings.json,
# which runs every 60s in every session (statusLine.refreshInterval), so a
# reloaded window shows the right tag within a minute. Prints nothing: the
# status line's stdout is the status line. No-op outside tmux.
[ -n "$TMUX" ] || exit 0
sock=${TMUX%%,*}
cur=$(tmux -S "$sock" show -gv set-titles-string 2>/dev/null) || exit 0
[ -n "$cur" ] || exit 0
case $cur in
  *' ') tmux -S "$sock" set -g set-titles-string "${cur% }" ;;
  *)    tmux -S "$sock" set -g set-titles-string "$cur " ;;
esac

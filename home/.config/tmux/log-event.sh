#!/usr/bin/env bash
# One line in the tmux hooks' log, for a hook that has only something to
# say (declared in ~/.tmux.conf; the hooks that also do something log from
# their own scripts, into the same file):
#
#   log-event.sh focus-in /dev/pts/1 session=backend
#   -> ~/.dotfiles/.logs/<UTC day>_tmux_hooks/events.log
#      2026-09-30T14:45:38Z focus-in /dev/pts/1 session=backend
#
# The file is the terminal's side of the story as tmux hears it: attaches,
# detaches, session switches, focus in and out. The ntfy hook decides from
# tmux's focus flag (home/.claude/ntfy-stop.sh), and a terminal that stops
# reporting focus shows here as the moment the focus lines stop.
set -eu
# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/../../../scripts/lib/event_log.sh"
event_log_note tmux_hooks "$@"

#!/usr/bin/env bash
# event_log_note.sh -- the repo's event log (scripts/lib/event_log.sh) for a
# caller that cannot source a shell library: a claude mod
# (home/.claude/mods/*), whose hooks module runs programs by their arguments.
#
#   event_log_note.sh <name> <message...>   one line in today's log of <name>
#
#   event_log_note.sh claude_ntfy 'backend ($3)' 'stop: watched now, no push'
#   -> ~/.dotfiles/.logs/<UTC day>_claude_ntfy/events.log
#      2026-11-19T19:02:11Z backend ($3) stop: watched now, no push
#
# The day's first line also prunes the old logs, as any log's start does
# (event_log_start): whatever writes logs keeps them in bounds, and a mod
# need not know that. After the line, so a prune that fails costs no line;
# about 0.1 s, once a day. Nothing on stdout; a log that cannot be written
# or pruned is said on stderr with exit 1.
set -eu

# shellcheck source=scripts/lib/event_log.sh
. "${0%/*}/lib/event_log.sh"

[ $# -ge 2 ] || {
  echo "event_log_note.sh: usage: event_log_note.sh <name> <message...>" >&2
  exit 64
}
event_log_note "$@" || {
  echo "event_log_note.sh: cannot log under $EVENT_LOG_ROOT" >&2
  exit 1
}
event_log_prune >/dev/null || {
  echo "event_log_note.sh: the line is logged, but pruning $EVENT_LOG_ROOT failed (scripts/prune_logs.sh)" >&2
  exit 1
}

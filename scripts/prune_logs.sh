#!/usr/bin/env bash
#
# prune_logs.sh -- remove old event logs from ~/.dotfiles/.logs. Run by
# whatever starts an event log (scripts/lib/event_log.sh,
# home/.hammerspoon/event_log.lua), so nothing has to schedule it.
#
#   prune_logs.sh            once a UTC day: a no-op if it ran today
#   prune_logs.sh --force    now
#
# What goes: a directory that is all of
#   named <YYYYMMDD_HHMMSS>_<name>   what the event logs make
#   holding events.log and nothing else
#   not the newest of its <name>
#   last written over KEEP_DAYS days ago
#
#   20260801_101500_appearance_sh/events.log   60 days     removed
#   20260929_234931_bell_banner_repro/         README.md   kept: a record of
#                                                          work, however old
#   20260815_080000_dbus_session/events.log    45 days,    kept: the bus that
#                                              newest      runs writes to it
#
# The newest of a name stays whatever its age: a daemon started in August
# logs to August's directory for as long as it runs, and its file may be
# silent for months. Age is the file's last write, not the name's date, for
# the same reason.
#
# Logs what it removed to ~/.dotfiles/.logs/<UTC>_prune_logs/events.log; a
# run that removes nothing leaves no directory.

set -euo pipefail

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/lib/event_log.sh"

KEEP_DAYS=30
root=$EVENT_LOG_ROOT

[ -d "$root" ] || { echo "prune_logs.sh: $root missing" >&2; exit 1; }
today=$(date -u +%Y%m%d)
case "${1:-}" in
  "") ! event_log_pruned "$today" || exit 0 ;;
  --force) ;;
  *) echo "prune_logs.sh: unknown argument '$1': prune_logs.sh [--force]" >&2; exit 1 ;;
esac
printf '%s\n' "$today" > "$root/.pruned"
cd "$root"

# Every directory of the form event_log_start makes that is not the newest
# of its name: sorted, the UTC prefix puts the newest last.
#   20260801_101500_appearance_sh  -> name appearance_sh (from character 17)
older=$(
  for d in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]_*/; do
    [ -d "$d" ] || continue # the pattern itself, when nothing matches it
    printf '%s\n' "${d%/}"
  done | sort | awk '{ name = substr($0, 17); if (name in last) print last[name]; last[name] = $0 }'
)

# The event logs last written over KEEP_DAYS days ago, in one find for them
# all, a path a line:  ./20260801_101500_appearance_sh/events.log
old=$(find . -mindepth 2 -maxdepth 2 -type f -name events.log -mtime +"$KEEP_DAYS")
nl='
'

removed=0
while IFS= read -r d; do
  case "$nl$old$nl" in
    *"$nl./$d/events.log$nl"*) ;;
    *) continue ;;
  esac
  [ "$(ls -A "$d")" = "events.log" ] || continue
  # The first removal starts this run's own log; not before, so a run with
  # nothing to do leaves nothing behind.
  [ "$removed" -gt 0 ] || event_log_start prune_logs --no-prune
  rm -r "./$d"
  log "removed $d"
  removed=$((removed + 1))
done <<< "$older"

if [ "$removed" -gt 0 ]; then
  log "removed $removed event log(s) last written over $KEEP_DAYS days ago"
fi

# shellcheck shell=bash
#
# event_log.sh -- the event log of a script that runs on its own (a hook, a
# daemon, a job), the repo's rule for those (AGENTS.md). Sourced, not run;
# home/.hammerspoon/event_log.lua is the same for Hammerspoon modules.
#
#   . "$(dirname "$0")/lib/event_log.sh"
#   event_log_start appearance_sh
#   log "theme -> gruvbox-dark"
#   -> ~/.dotfiles/.logs/20260930_002944_appearance_sh/events.log
#      2026-09-30T00:29:44Z theme -> gruvbox-dark
#
# One directory per run, named by its UTC start, or per UTC day for what
# runs many times a day (event_log_daily). The first log started on a UTC
# day also prunes the old ones (prune_logs.sh, which says what goes), so
# whatever writes logs keeps them in bounds, with no scheduler to install on
# each machine.
#
# Runs under bash 3.2 too: from Hammerspoon and launchd `env bash` finds
# macOS's own. On bash 4.2 and later a line is logged without a fork, for
# the hooks that run at every prompt.

EVENT_LOG_ROOT="$HOME/.dotfiles/.logs"

# _event_log_time <variable> <strftime format>: the UTC time now into the
# variable. printf's %(...)T is a builtin from bash 4.2 on; 3.2 forks date.
_event_log_time() {
  if [ "${BASH_VERSINFO[0]}" -gt 4 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 2 ]; }; then
    TZ=UTC printf -v "$1" "%($2)T" -1
  else
    printf -v "$1" '%s' "$(date -u "+$2")"
  fi
}

# event_log_pruned <YYYYMMDD>: whether the logs were pruned on that UTC day,
# which prune_logs.sh notes in .pruned. Read with builtins alone: this is
# asked at every start of a log, a prune is due at one in a day's.
event_log_pruned() {
  local last=
  if [ -f "$EVENT_LOG_ROOT/.pruned" ]; then
    IFS= read -r last < "$EVENT_LOG_ROOT/.pruned" || true
  fi
  [ "$last" = "$1" ]
}

# event_log_prune: prune the old logs unless that was done today.
event_log_prune() {
  local today
  _event_log_time today '%Y%m%d'
  event_log_pruned "$today" || "$(dirname "${BASH_SOURCE[0]}")/../prune_logs.sh"
}

# event_log_start <name> [--no-prune]: make this run's directory; sets
# EVENT_LOG_FILE. A prune that fails fails the caller: a log directory that
# cannot be kept in bounds is a finding. --no-prune is for what must not
# wait on one or fail with it.
event_log_start() {
  local now dir
  _event_log_time now '%Y%m%d_%H%M%S'
  dir="$EVENT_LOG_ROOT/${now}_$1"
  EVENT_LOG_FILE="$dir/events.log"
  mkdir -p "$dir" || return 1
  [ "${2:-}" = "--no-prune" ] || event_log_prune || return 1
}

# event_log_daily <name> [--no-prune]: as event_log_start, but one directory
# per UTC day, named by the day's first event: for a hook that runs at every
# turn, where a directory a run would be hundreds a day.
#
#   13:40 first event today  -> 20260930_134002_claude_ntfy/ is made
#   13:52, 18:07, ...        -> the same directory, found by its day
#   00:03 tomorrow           -> 20261001_000311_claude_ntfy/
#
# Finding the day's directory is a glob, no fork, so it is cheap to ask for
# before every line; a process that outlives midnight then moves on with
# the day. Two first events in the same second or two make two directories;
# the earlier sorts first and takes every later line.
event_log_daily() {
  local today dir
  _event_log_time today '%Y%m%d'
  for dir in "$EVENT_LOG_ROOT/${today}_"[0-9][0-9][0-9][0-9][0-9][0-9]"_$1"; do
    if [ -d "$dir" ]; then
      EVENT_LOG_FILE="$dir/events.log"
      return 0
    fi
  done
  event_log_start "$@"
}

# log <message>: a UTC-stamped line, to the log and to stdout.
log() {
  local stamp
  _event_log_time stamp '%Y-%m-%dT%H:%M:%SZ'
  printf '%s %s\n' "$stamp" "$*" >> "$EVENT_LOG_FILE"
  printf '%s %s\n' "$stamp" "$*"
}

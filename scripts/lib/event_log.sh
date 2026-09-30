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
# One directory per run, named by its UTC start. The first log started on a
# UTC day also prunes the old ones (prune_logs.sh, which says what goes), so
# whatever writes logs keeps them in bounds, with no scheduler to install on
# each machine.
#
# Runs under bash 3.2 too: from Hammerspoon and launchd `env bash` finds
# macOS's own.

EVENT_LOG_ROOT="$HOME/.dotfiles/.logs"

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

# event_log_start <name> [--no-prune]: make the directory; sets
# EVENT_LOG_FILE. A prune that fails fails the caller: a log directory that
# cannot be kept in bounds is a finding. --no-prune is for what must not
# wait on one or fail with it.
event_log_start() {
  local now dir
  now=$(date -u +%Y%m%d_%H%M%S)
  dir="$EVENT_LOG_ROOT/${now}_$1"
  EVENT_LOG_FILE="$dir/events.log"
  mkdir -p "$dir" || return 1
  if [ "${2:-}" != "--no-prune" ] && ! event_log_pruned "${now%%_*}"; then
    "$(dirname "${BASH_SOURCE[0]}")/../prune_logs.sh" || return 1
  fi
}

# log <message>: a UTC-stamped line, to the log and to stdout.
log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$EVENT_LOG_FILE"
}

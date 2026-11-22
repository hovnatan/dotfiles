#!/usr/bin/env bash
# What iina_night_shift.lua runs when IINA launches and quits, against
# Hammerspoon doubles, so no IINA, macOS or Hammerspoon is needed and it runs
# in CI on Linux and macOS: which verb of night_shift.swift each event asks
# for, their order when events come faster than the script, and the alert
# when the script fails, hangs or does not start.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start iina_night_shift_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/iina_night_shift_test.lua" "$REPO" "$EVENT_LOG_FILE"

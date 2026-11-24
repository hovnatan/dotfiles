#!/usr/bin/env bash
# What mpv_night_shift.lua runs while mpv is open and once none is, against
# Hammerspoon doubles, so no mpv, macOS or Hammerspoon is needed and it runs
# in CI on Linux and macOS: which verb of night_shift.swift each check asks
# for, their order when checks come faster than the script, and the alert
# when the script fails, hangs or does not start.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start mpv_night_shift_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/mpv_night_shift_test.lua" "$REPO" "$EVENT_LOG_FILE"

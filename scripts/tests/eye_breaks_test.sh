#!/usr/bin/env bash
# The eye-break timing (when a break is due, what counts as rest, what the
# menu bar and badge show) on a made-up clock, and display_wake.lua's reading
# of saved `pmset -g assertions` output. Neither makes a Hammerspoon call
# there, so this needs no macOS UI and runs in CI on Linux and macOS.
# eye_breaks.lua, the part that draws, is checked by hand on a Mac.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start eye_breaks_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/eye_breaks_test.lua" "$REPO" "$EVENT_LOG_FILE"

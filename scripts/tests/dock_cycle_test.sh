#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/dock_cycle.lua home/.hammerspoon/alttab.lua
# The Dock click's walk through the front app's windows against Hammerspoon
# doubles, so no macOS UI, Dock or Hammerspoon is needed and it runs in CI on
# Linux and macOS: when the tap runs, which clicks are taken, the order the
# windows come forward in, and how a failure is said.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start dock_cycle_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/dock_cycle_test.lua" "$REPO" "$EVENT_LOG_FILE"

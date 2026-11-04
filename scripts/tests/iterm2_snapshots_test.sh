#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/iterm2_snapshots.lua home/.hammerspoon/failure.lua scripts/tests/iterm2_snapshots_test.lua scripts/lib/*
# The Hammerspoon snapshot timer against doubles, so no macOS UI, iTerm2 or
# Hammerspoon is needed and it runs in CI on Linux and macOS: an error in one
# tick is alerted and logged, and the next tick still runs.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start iterm2_snapshots_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/iterm2_snapshots_test.lua" "$REPO" "$EVENT_LOG_FILE"

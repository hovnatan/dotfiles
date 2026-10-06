#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/iterm2_bell_banners.lua home/.hammerspoon/clear_notifications.lua scripts/lib/*
# Exercise the real Lua module with explicit AX events and task results;
# no macOS UI is needed, so these races run in CI on Linux and macOS.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start iterm2_bell_banners_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: Lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/iterm2_bell_banners_test.lua" "$REPO" "$EVENT_LOG_FILE"

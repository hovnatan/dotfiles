#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/url_dispatcher.lua home/.hammerspoon/local_config.lua home/.hammerspoon/failure.lua scripts/tests/url_dispatcher_test.lua scripts/lib/*
# Which Chrome profile a clicked link opens in, and how the machine-private
# config loads, against Hammerspoon doubles (url_dispatcher_test.lua), so no
# macOS UI or Chrome is needed and it runs in CI on Linux and macOS.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start url_dispatcher_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/url_dispatcher_test.lua" "$REPO" "$EVENT_LOG_FILE"

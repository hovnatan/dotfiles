#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/print_guard.lua scripts/lib/*
# print() under a killed `hs` client, against a double of hs.ipc's print
# hook, so no Hammerspoon is needed and it runs in CI on Linux and macOS:
# the dead client is unregistered before the line is sent, the live ones
# still get it, and a send that fails anyway is not a stack overflow.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start print_guard_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/print_guard_test.lua" "$REPO" "$EVENT_LOG_FILE"

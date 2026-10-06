#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/ssh_command.lua scripts/lib/*
# Exercise home/.hammerspoon/ssh_command.lua, the parser behind iTerm2's
# Cmd-T in an ssh tab (iterm2_keys.lua). Pure Lua, so it runs in CI on
# Linux and macOS.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start ssh_command_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || { log "ERROR: Lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"; exit 1; }
lua "$REPO/scripts/tests/ssh_command_test.lua" "$REPO" "$EVENT_LOG_FILE"

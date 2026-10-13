#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/ssh_command.py scripts/tests/ssh_command_test.py scripts/lib/*
# Exercise home/.hammerspoon/ssh_command.py, the parser behind iTerm2's
# Cmd-T in an ssh tab (iterm2_api.py) and the saved ssh arrangements. No
# iterm2 import, so plain python3 runs it in CI on Linux and macOS.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start ssh_command_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v python3 >/dev/null || {
  log "ERROR: python3 is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
python3 "$REPO/scripts/tests/ssh_command_test.py" "$REPO" "$EVENT_LOG_FILE"

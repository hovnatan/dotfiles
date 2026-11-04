#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/switcher.lua home/.hammerspoon/iterm2_switcher.lua home/.hammerspoon/ghostty_switcher.lua
# The middle-click window pickers against Hammerspoon doubles, so no macOS UI,
# terminal or Hammerspoon is needed and it runs in CI on Linux and macOS: which
# clicks are taken, what the picker gets, and how a failure is said.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start switcher_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/switcher_test.lua" "$REPO" "$EVENT_LOG_FILE"

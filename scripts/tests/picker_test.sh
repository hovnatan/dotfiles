#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/picker.lua home/.hammerspoon/picker.html
# The picker panel against Hammerspoon doubles, so no macOS UI or Hammerspoon is
# needed and it runs in CI on Linux and macOS: an opening stays unseen until its
# page has painted, and a page that never does cannot keep the keyboard.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start picker_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/picker_test.lua" "$REPO" "$EVENT_LOG_FILE"

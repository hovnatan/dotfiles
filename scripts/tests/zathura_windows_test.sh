#!/usr/bin/env bash
# When zathura_windows.lua's Cmd-` tap runs, against Hammerspoon doubles, so
# no Zathura, macOS UI or Hammerspoon is needed and it runs in CI on Linux
# and macOS: which app events start and stop it, and which of them ask macOS
# for the frontmost app (none under the lock screen, where asking prints an
# error to the Console).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start zathura_windows_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v lua >/dev/null || {
  log "ERROR: lua is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
lua "$REPO/scripts/tests/zathura_windows_test.lua" "$REPO" "$EVENT_LOG_FILE"

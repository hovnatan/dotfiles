#!/usr/bin/env bash
# check.sh covers: home/.hammerspoon/iterm2_api.lua home/.hammerspoon/failure.lua home/.hammerspoon/iterm2_api.py home/.hammerspoon/ssh_command.py home/.hammerspoon/clear_notifications.lua scripts/tests/iterm2_api_test.py scripts/tests/iterm2_api_test.lua scripts/lib/*
# iterm2_api.py and the Hammerspoon module that runs it, in two halves, each
# against doubles, so no macOS UI, iTerm2 or uv is needed and both run in CI
# on Linux and macOS:
#   iterm2_api_test.py   which bells get a banner and when it closes; what
#                        Cmd-T opens; the switcher's window list and order
#   iterm2_api_test.lua  the Hammerspoon side: events in, banners, window
#                        lists and the script's lifecycle out
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start iterm2_api_test --no-prune
log "regression log: $EVENT_LOG_FILE"
for tool in lua python3; do
  command -v "$tool" >/dev/null || {
    log "ERROR: $tool is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
    exit 1
  }
done
status=0
python3 "$REPO/scripts/tests/iterm2_api_test.py" "$REPO" "$EVENT_LOG_FILE" || status=1
lua "$REPO/scripts/tests/iterm2_api_test.lua" "$REPO" "$EVENT_LOG_FILE" || status=1
exit "$status"

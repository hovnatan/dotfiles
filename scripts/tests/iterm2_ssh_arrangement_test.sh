#!/usr/bin/env bash
# check.sh covers: scripts/lib/iterm2_ssh_arrangement.py scripts/iterm2_ssh_arrangement.sh home/.hammerspoon/ssh_command.py scripts/tests/iterm2_ssh_arrangement_test.py
# Exercise the pure part of scripts/lib/iterm2_ssh_arrangement.py: iTerm2's
# tabs in, the saved lines out, with the remote tmux lookup faked and a
# stub iterm2 module. No iTerm2, uv or ssh, so it runs in CI on Linux and
# macOS.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep CI output in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start iterm2_ssh_arrangement_test --no-prune
log "regression log: $EVENT_LOG_FILE"
command -v python3 >/dev/null || {
  log "ERROR: python3 is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
  exit 1
}
python3 "$REPO/scripts/tests/iterm2_ssh_arrangement_test.py" "$REPO" "$EVENT_LOG_FILE"

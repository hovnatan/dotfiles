#!/usr/bin/env bash
# check.sh covers: scripts/tmux_history.py scripts/lib/event_log.py scripts/tests/tmux_history_test.py home/.config/tmux/tmux.conf
#
# tmux_history_test.sh -- the tmux history tracker (scripts/tmux_history.py):
# its parsing and its answers to made-up notifications, then the tracker
# itself, started by throwaway tmux servers from its tmux.conf line, with
# clients in ptys. The stages are listed in tmux_history_test.py's
# docstring. Needs tmux and python3 (3.11 or later); about 5 s.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep the log in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start tmux_history_test --no-prune
log "regression log: $EVENT_LOG_FILE"
for cmd in tmux python3; do
  command -v "$cmd" >/dev/null || {
    log "ERROR: $cmd is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
    exit 1
  }
done
python3 "$REPO/scripts/tests/tmux_history_test.py" "$REPO" "$EVENT_LOG_FILE"

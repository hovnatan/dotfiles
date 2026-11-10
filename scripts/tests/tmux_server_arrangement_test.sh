#!/usr/bin/env bash
# check.sh covers: scripts/tmux_server_arrangement.py scripts/lib/tmux_arrangement.py scripts/lib/event_log.py scripts/tests/tmux_server_arrangement_test.py home/.config/tmux/tmux.conf
#
# tmux_server_arrangement_test.sh -- the tmux snapshots and their restore
# (scripts/tmux_server_arrangement.py): the file format and restore's pick,
# then the snapshot run as tmux.conf starts it, and restore and replace, on
# throwaway tmux servers. The stages are listed in
# tmux_server_arrangement_test.py's docstring. Needs tmux and python3 (3.11
# or later); about 10 s.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep the log in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start tmux_server_arrangement_test --no-prune
log "regression log: $EVENT_LOG_FILE"
for cmd in tmux python3; do
  command -v "$cmd" >/dev/null || {
    log "ERROR: $cmd is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
    exit 1
  }
done
python3 "$REPO/scripts/tests/tmux_server_arrangement_test.py" "$REPO" "$EVENT_LOG_FILE"

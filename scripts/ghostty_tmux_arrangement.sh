#!/usr/bin/env bash
# Save the tmux sessions of Ghostty's windows, local ones and those over ssh,
# and bring them back in new windows. The logic, and what a tab is saved as,
# is in scripts/lib/ghostty_tmux_arrangement.py.
#
#   ghostty_tmux_arrangement.sh save [<name>]     every window; <name> defaults
#                                                 to "all"
#   ghostty_tmux_arrangement.sh restore [<name>]  a new window per saved one,
#                                                 skipping sessions already open
#   ghostty_tmux_arrangement.sh replace [<name>]  the saved windows in place of
#                                                 every window open; refused
#                                                 under Ghostty, or where a
#                                                 running program would die
#   ghostty_tmux_arrangement.sh snapshot          every window as auto-<UTC time>,
#                                                 keeping the newest 2016;
#                                                 Hammerspoon runs it every 10
#                                                 minutes
#
# Saved to ~/.local/state/ghostty_tmux_arrangements/<name>.txt, a block of
# commands per window: machine-local, since it names hosts.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

[ "$(uname)" = Darwin ] || {
  echo "ghostty_tmux_arrangement.sh: its AppleScript is macOS only" >&2
  exit 1
}
command -v python3 >/dev/null || {
  echo "ghostty_tmux_arrangement.sh: python3 is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix" >&2
  exit 1
}

# A snapshot runs 144 times a day: one log directory a day, not a run.
if [ "${1:-}" = snapshot ]; then
  event_log_daily ghostty_tmux_snapshot
else
  event_log_start ghostty_tmux_arrangement
fi
echo "log: $EVENT_LOG_FILE"
exec python3 "$REPO/scripts/lib/ghostty_tmux_arrangement.py" "$EVENT_LOG_FILE" "$@"

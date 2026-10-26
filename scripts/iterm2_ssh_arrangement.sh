#!/usr/bin/env bash
# Save the tabs of iTerm2's windows as the ssh logins (and remote tmux
# sessions) that bring them back, and restore them into new windows. The
# logic, and what a tab is saved as, is in
# scripts/lib/iterm2_ssh_arrangement.py, on iTerm2's Python API.
#
#   iterm2_ssh_arrangement.sh save [<name>]           every window; <name>
#                                                     defaults to "all"
#   iterm2_ssh_arrangement.sh save <name> <prefix>    the one window whose
#                                                     title starts with <prefix>
#   iterm2_ssh_arrangement.sh restore [<name>]        a new window per saved one
#   iterm2_ssh_arrangement.sh replace [<name>]        iTerm2 quit and launched,
#                                                     then those windows alone;
#                                                     run from another terminal
#   iterm2_ssh_arrangement.sh snapshot                every window as
#                                                     auto-<UTC time>, keeping
#                                                     the newest 144 (a day at
#                                                     one per 10 minutes); Hammerspoon
#                                                     runs it every 10 minutes
#
# Saved to ~/.local/state/iterm2_ssh_arrangements/<name>.txt, a block of
# commands per window: machine-local, since it names hosts. A <name> with a
# "/" or ".txt" is that file's path instead, so the shell can complete it.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

[ "$(uname)" = Darwin ] || {
  echo "iterm2_ssh_arrangement.sh: iTerm2 is macOS only" >&2
  exit 1
}
command -v uv >/dev/null || {
  echo "iterm2_ssh_arrangement.sh: uv is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix" >&2
  exit 1
}

# A snapshot runs 144 times a day: one log directory a day, not a run.
if [ "${1:-}" = snapshot ]; then
  event_log_daily iterm2_ssh_snapshot
else
  event_log_start iterm2_ssh_arrangement
fi
echo "log: $EVENT_LOG_FILE"
# uv reads the script's pinned iterm2 from its inline metadata.
exec uv run --quiet --script "$REPO/scripts/lib/iterm2_ssh_arrangement.py" "$EVENT_LOG_FILE" "$@"

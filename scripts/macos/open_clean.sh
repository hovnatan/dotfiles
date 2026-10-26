#!/usr/bin/env bash
#
# open_clean.sh -- `open` an app with the environment a Dock or Finder launch
# gives it, not the caller's. `open` hands the calling shell's environment to
# an app it starts, and the app hands it on to everything it starts in turn:
#
#   Claude Code Bash tool (CLAUDECODE=1, CLAUDE_CODE_CHILD_SESSION=1, ...)
#     --open -a Hammerspoon-->  Hammerspoon, with all of it, for days
#       --iTerm2 hotkey-->      iTerm2, with all of it
#         --new tab-->          claude: "Transcript saving is off -
#                               inherited CLAUDE_CODE_CHILD_SESSION marker"
#
# (2026-10-07 -> 2026-10-12; again 2026-10-26 by iterm2_ssh_arrangement.sh
# replace, which now launches iTerm2 through this.) So relaunch a GUI app from a
# shell with this:
#
#   ~/.dotfiles/scripts/macos/open_clean.sh -a Hammerspoon
#
# Arguments go to open(1) unchanged; open(1) runs with an empty environment.
# launchd then fills in the app's, as for a Dock launch: the standard set
# (HOME, USER, LOGNAME, SHELL from the directory, TMPDIR, PATH, ...) plus the
# user domain's `launchctl setenv` variables, SSH_AUTH_SOCK among them. Passing
# none of the caller's keeps each value launchd's own: a kept SHELL was the
# caller's (Nix bash from a Claude Code Bash tool) where the Dock gives /bin/zsh.
# Checked 2026-10-26, Ghostty launched so against Telegram launched at login:
# the same variables, the same values.
#
# Logs each launch to ~/.dotfiles/.logs/<UTC>_open_clean/events.log
# (scripts/lib/event_log.sh).

set -euo pipefail

[ "$(uname)" = "Darwin" ] || {
  echo "open_clean.sh: macOS only" >&2
  exit 1
}
[ $# -gt 0 ] || {
  echo "usage: open_clean.sh <open(1) arguments>, e.g. -a Hammerspoon" >&2
  exit 1
}

. "$(dirname "$0")/../lib/event_log.sh"
event_log_start open_clean

log "open $* (empty env; launchd fills it in)"
env -i /usr/bin/open "$@"
log "launched"

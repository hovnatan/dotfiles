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
# (2026-10-07 -> 2026-10-12.) So relaunch a GUI app from a shell with this:
#
#   ~/.dotfiles/scripts/macos/open_clean.sh -a Hammerspoon
#
# Arguments go to open(1) unchanged. Kept: the variables launchd gives an app
# (HOME, USER, LOGNAME, SHELL, TMPDIR, SSH_AUTH_SOCK, LANG,
# __CF_USER_TEXT_ENCODING) and launchd's PATH; everything else is dropped.
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

# Each kept variable that is set, as NAME=value for env -i. An unset one is
# left out, as launchd would.
keep=()
for name in HOME USER LOGNAME SHELL TMPDIR SSH_AUTH_SOCK LANG __CF_USER_TEXT_ENCODING; do
  if [ -n "${!name+x}" ]; then
    keep+=("$name=${!name}")
  fi
done

log "open $* (env: ${keep[*]%%=*} PATH)"
env -i "${keep[@]}" PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/open "$@"
log "launched"

#!/usr/bin/env bash
#
# zathura_recolor.sh -- zathura's r key: recolouring off and on in one
# window, the margins with the pages.
#
#   zathura_recolor.sh org.pwmt.zathura.PID-<pid>    as zathurarc's map gives it ($DBUS)
#
# zathura's own toggle (the `recolor` function, still on ctrl-r) changes the
# pages alone, which leaves the margins in the theme's page colour. No
# setting ties the two, and a key runs one function, so r runs this, which
# sends the window both. scripts/lib/zathura_window.sh has the two states
# and how a window's is known. Both are sent in full each time, so a window
# that ctrl-r put out of step is right again at the next r.
#
# Logs to ~/.dotfiles/.logs/<UTC day>_zathura_recolor/events.log.

set -euo pipefail

# From zathura PATH is the system's alone.
PATH="$HOME/.nix-profile/bin:$PATH"

here=$(dirname "$0")
# shellcheck source=scripts/lib/event_log.sh
. "$here/lib/event_log.sh"
# No prune: the day's first would run on a key press.
event_log_daily zathura_recolor --no-prune
# shellcheck source=scripts/lib/zathura_window.sh
. "$here/lib/zathura_window.sh"

name=${1:-}
[[ $name =~ ^org\.pwmt\.zathura\.PID-[0-9]+$ ]] \
  || die "usage: zathura_recolor.sh org.pwmt.zathura.PID-<pid> (got '$name')"

# The margins first: a colour file that is missing stops this with nothing sent.
if zathura_plain "$name"; then
  zathura_send_sets "$name" "$ZATHURA_THEME"
  zathura_command "$name" "set recolor true"
  zathura_plain_forget "$name"
  log "$name recoloured"
else
  zathura_send_plain "$name"
  zathura_command "$name" "set recolor false"
  zathura_plain_note "$name"
  log "$name plain"
fi
zathura_plain_sweep

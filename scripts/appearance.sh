#!/usr/bin/env bash
#
# appearance.sh -- make the programs that cannot follow the system's light or
# dark appearance by themselves follow it. The terminals and nvim can; Claude
# Code (with a custom theme) and zathura cannot.
#
#   appearance.sh            the system's appearance (macOS only)
#   appearance.sh light|dark that one; the only form on Linux
#
#   home/.hammerspoon/appearance.lua     home/.tmux.conf hooks       by hand,
#   (macOS: the switch, load, wake)      (the attached terminal's    install
#                     \                   theme; reaches over ssh)     /
#                      v                          v                   v
#                                  appearance.sh <mode>
#                                   |                |
#      ~/.claude/themes/gruvbox.json                ~/.config/zathura/theme
#        -> gruvbox-<mode>.json                       -> gruvbox-<mode>
#      Claude Code watches the directory,           read by zathura at start;
#      so sessions that run recolour                each window that is open is
#      at once                                      sent the file's `set` lines
#                                                   over D-Bus
#
# Both links are machine-local (.gitignore): which appearance a machine is
# in is its own state. The tracked configs name the link, never a mode, so
# nothing tracked changes at sunset; settings.json used to, with
# "theme": "custom:gruvbox-dark".
#
# zathura is reached over the session bus that
# scripts/macos/dbus_session.sh keeps at ~/.cache/bus, where it registers as
# org.pwmt.zathura.PID-<pid>. A window opened before that bus ran is not on
# it and keeps its colours until reopened.
#
# Logs to ~/.dotfiles/.logs/<UTC>_appearance_sh/events.log (scripts/lib/event_log.sh).

set -euo pipefail

# From Hammerspoon and launchd PATH is the system's alone.
PATH="$HOME/.nix-profile/bin:$PATH"

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/lib/event_log.sh"
event_log_start appearance_sh
die() { log "ERROR $*" >&2; exit 1; }

# --- which appearance ---------------------------------------------------------

case "${1:-}" in
  light | dark) mode=$1 ;;
  "")
    [ "$(uname)" = "Darwin" ] || die "no appearance given: appearance.sh light|dark (only macOS can be asked for its own)"
    # AppleInterfaceStyle is "Dark" in dark mode and not there at all in light.
    if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then mode=dark; else mode=light; fi
    ;;
  *) die "unknown appearance '$1': appearance.sh [light|dark]" ;;
esac

# --- the links ----------------------------------------------------------------

# Point link $1 at $2, a file next to it. Renamed into place, so a reader
# never finds the link missing.
point() {
  local link=$1 target=$2 dir
  dir=$(dirname "$link")
  [ -d "$dir" ] || die "$dir missing: install with ~/.dotfiles/scripts/setup_user_symlinks.sh"
  [ -f "$dir/$target" ] || die "$dir/$target missing"
  if [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then
    log "$link -> $target already"
    return
  fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    die "$link is a file, not a link: move it aside"
  fi
  ln -s "$target" "$link.new.$$"
  mv -f "$link.new.$$" "$link"
  log "$link -> $target"
}

point "$HOME/.claude/themes/gruvbox.json" "gruvbox-$mode.json"
point "$HOME/.config/zathura/theme" "gruvbox-$mode"

# --- the zathura windows that are open ----------------------------------------

if ! command -v zathura >/dev/null; then
  log "no zathura on this machine"
  exit 0
fi
bus="${XDG_RUNTIME_DIR:-$HOME/.cache}/bus"
command -v dbus-send >/dev/null || die "dbus-send missing: apply the Nix package set (dotup)"
[ -S "$bus" ] || die "no session bus at $bus: install with ~/.dotfiles/scripts/setup_user_symlinks.sh"
send() { dbus-send --bus="unix:path=$bus" --print-reply --reply-timeout=3000 "$@"; }

names=$(send --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
  | sed -n 's/.*"\(org\.pwmt\.zathura\.PID-[0-9]*\)".*/\1/p')
if [ -z "$names" ]; then
  log "no zathura window on the bus (one opened before the bus ran has to be reopened)"
  exit 0
fi

# Its `set` lines one by one, not zathura's SourceConfig: that reads all of
# zathurarc again and would undo what was changed in the window since
# (zoom mode, a statusbar toggled on).
for name in $names; do
  while IFS= read -r line; do
    case "$line" in
      set\ *) ;;
      "" | \#*) continue ;;
      *) die "$HOME/.config/zathura/theme: not a set line: $line" ;;
    esac
    reply=$(send --dest="$name" /org/pwmt/zathura org.pwmt.zathura.ExecuteCommand "string:$line") \
      || die "$name: no answer to '$line'"
    case "$reply" in
      *"boolean true"*) ;;
      *) die "$name refused '$line': $reply" ;;
    esac
  done < "$HOME/.config/zathura/theme"
  log "$name recoloured $mode"
done

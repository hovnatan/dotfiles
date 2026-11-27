# shellcheck shell=bash
#
# zathura_window.sh -- a zathura window from outside: its colours sent over
# D-Bus, and whether it is plain (recolouring off, the document in its own
# colours). Sourced, not run, by scripts/appearance.sh and
# scripts/zathura_recolor.sh, after scripts/lib/event_log.sh: its die is how
# these end.
#
#                 pages                   margins (default-bg)
#   recoloured    the theme's colours     the theme's page colour
#   plain         the document's own      white; black in the dark theme
#
# The colours are in ~/.config/zathura: `theme`, the link appearance.sh
# points at gruvbox-light or gruvbox-dark, and beside what it points at
# <that>-plain, the settings a plain window has over the theme's.
#
# A window is on the session bus as org.pwmt.zathura.PID-<pid> and runs what
# it is sent as if typed after ":". It cannot be asked for a setting, so a
# window turned plain is noted:
#
#   ~/.cache/zathura_plain/<pid>    the start time of that process, so a
#                                   later process with the same pid is not
#                                   taken for the window

ZATHURA_BUS="${XDG_RUNTIME_DIR:-$HOME/.cache}/bus"
ZATHURA_THEME="$HOME/.config/zathura/theme"
ZATHURA_PLAIN_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zathura_plain"

zathura_bus_send() { dbus-send --bus="unix:path=$ZATHURA_BUS" --print-reply --reply-timeout=3000 "$@"; }

# zathura_command <bus name> <command>: run the command in that window.
zathura_command() {
  local reply
  reply=$(zathura_bus_send --dest="$1" /org/pwmt/zathura org.pwmt.zathura.ExecuteCommand "string:$2") \
    || die "$1: no answer to '$2'"
  case "$reply" in
    *"boolean true"*) ;;
    *) die "$1 refused '$2': $reply" ;;
  esac
}

# zathura_send_sets <bus name> <file>: the file's `set` lines, one by one.
# Not zathura's SourceConfig: that reads all of zathurarc again and would
# undo what was changed in the window since (zoom mode, a statusbar toggled
# on).
zathura_send_sets() {
  local line
  [ -f "$2" ] || die "$2 missing"
  while IFS= read -r line; do
    case "$line" in
      set\ *) zathura_command "$1" "$line" ;;
      "" | \#*) ;;
      *) die "$2: not a set line: $line" ;;
    esac
  done <"$2"
}

# zathura_send_plain <bus name>: the plain settings of the theme that is on.
zathura_send_plain() {
  local theme
  theme=$(readlink "$ZATHURA_THEME") || die "$ZATHURA_THEME is not a link: run ~/.dotfiles/scripts/appearance.sh"
  zathura_send_sets "$1" "${ZATHURA_THEME%/*}/$theme-plain"
}

# zathura_apply <bus name>: the theme that is on, as that window has it.
zathura_apply() {
  zathura_send_sets "$1" "$ZATHURA_THEME"
  if zathura_plain "$1"; then zathura_send_plain "$1"; fi
}

# zathura_plain <bus name>: whether that window was turned plain.
zathura_plain() {
  local pid=${1##*-} started noted
  [ -f "$ZATHURA_PLAIN_DIR/$pid" ] || return 1
  started=$(ps -o lstart= -p "$pid") || return 1
  IFS= read -r noted <"$ZATHURA_PLAIN_DIR/$pid" || return 1
  [ "$noted" = "$started" ]
}

zathura_plain_note() {
  local pid=${1##*-} started
  started=$(ps -o lstart= -p "$pid") || die "$1: no process $pid"
  mkdir -p "$ZATHURA_PLAIN_DIR"
  printf '%s\n' "$started" >"$ZATHURA_PLAIN_DIR/$pid"
}

zathura_plain_forget() { rm -f "$ZATHURA_PLAIN_DIR/${1##*-}"; }

# zathura_plain_sweep: drop the notes of windows since closed.
zathura_plain_sweep() {
  local note
  for note in "$ZATHURA_PLAIN_DIR"/*; do
    [ -f "$note" ] || continue
    zathura_plain "org.pwmt.zathura.PID-${note##*/}" || rm "$note"
  done
}

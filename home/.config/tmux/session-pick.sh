#!/usr/bin/env bash
# prefix s: pick a session in an fzf popup and go to it.
#
#   prefix s -> a popup over the client, the pane each row would show below:
#       dots         3 windows  0s ago   (current)   the client's own session
#     > notes   1!   2 windows  3m ago               holding a bell: the one
#       build   0!   1 window   1h ago               that rang longest ago on
#       mail         4 windows  12s ago              top; then the rest, the
#       logs         1 window   2d ago   (attached)  one used last first
#   It opens on the second row, where prefix C-s (bell-next.sh) would go, so
#   Enter alone goes there. Typing narrows the rows; Enter goes to the row's
#   session, at the window that rang if it holds a bell; Esc closes.
#
# The client's own session holds a bell for a window of it out of view. The
# order below it is bell-sessions.sh's, as for prefix C-s; the label is in
# the bar's bell colours (window-status-bell-style, tmux.conf).
#
#   session-pick.sh <socket> <client> <the client's session id>
#       opens the popup, on itself with --pick: the three as arguments, so
#       no shell reads them
#   session-pick.sh --pick <socket> <client> <the client's session id>
#       in the popup: fzf over the rows, then the switch
#   session-pick.sh --rows <socket> <client> <the client's session id>
#       the rows as fzf is given them: <target> TAB <text>
#
# Runs under bash 3.2 too: run-shell finds bash on the server's PATH.
set -euo pipefail

mode=open
case ${1:-} in
  --pick | --rows)
    mode=${1#--}
    shift
    ;;
esac
[ "$#" -eq 3 ] || {
  echo "usage: session-pick.sh [--pick|--rows] <socket> <client> <the client's session id>" >&2
  exit 2
}
socket=$1 client=$2 here=$3
who="session-pick ${client#/dev/}"
# shellcheck source=home/.config/tmux/bell-sessions.sh
. "${0%/*}/bell-sessions.sh"

# ago <seconds>: $since is 45s, 12m, 3h or 2d
ago() {
  if [ "$1" -lt 60 ]; then
    since=${1}s
  elif [ "$1" -lt 3600 ]; then
    since=$(($1 / 60))m
  elif [ "$1" -lt 86400 ]; then
    since=$(($1 / 3600))h
  else
    since=$(($1 / 86400))d
  fi
}

rows() {
  local list now style paint id window attached used held windows name
  local byte='([0-9a-fA-F]{2})' wide=0 held_wide=0 label noun since mark row own='' rest=''
  now=${EPOCHSECONDS:-$(date +%s)}
  list=$(bell_sessions "$socket" "$here") || exit 1
  style=$(tmux -S "$socket" show-options -gv window-status-bell-style)
  [[ $style =~ ^fg=#$byte$byte$byte,bg=#$byte$byte$byte$ ]] \
    || stop "window-status-bell-style is '$style': the picker's label needs it as fg=#rrggbb,bg=#rrggbb"
  printf -v paint '\033[38;2;%d;%d;%d;48;2;%d;%d;%dm' "0x${BASH_REMATCH[1]}" "0x${BASH_REMATCH[2]}" \
    "0x${BASH_REMATCH[3]}" "0x${BASH_REMATCH[4]}" "0x${BASH_REMATCH[5]}" "0x${BASH_REMATCH[6]}"
  while IFS='|' read -r id _ _ _ _ held _ name; do
    [ "${#name}" -le "$wide" ] || wide=${#name}
    [ "${#held}" -le "$held_wide" ] || held_wide=${#held}
  done <<<"$list"
  while IFS='|' read -r id window attached used _ held windows name; do
    label=''
    if [ -n "$held" ]; then
      printf -v label '%s %s \033[0m%*s  ' "$paint" "$held" "$((held_wide - ${#held}))" ''
    elif [ "$held_wide" -gt 0 ]; then
      printf -v label '%*s' "$((held_wide + 4))" ''
    fi
    noun=windows
    [ "$windows" != 1 ] || noun=window
    mark=''
    [ "$attached" = 0 ] || mark='  (attached)'
    [ "$id" != "$here" ] || mark='  (current)'
    ago "$((now - used))"
    printf -v row '%s:%s\t%-*s  %s%s %-7s  %s ago%s\n' "$id" "$window" "$wide" "$name" "$label" \
      "$windows" "$noun" "$since" "$mark"
    if [ "$id" = "$here" ]; then own=$row; else rest+=$row; fi
  done <<<"$list"
  [ -n "$own" ] || stop "the client's session, $here, is not among the sessions of $socket"
  printf '%s%s' "$own" "$rest"
}

case $mode in
  rows) rows ;;
  open)
    exec tmux -S "$socket" display-popup -c "$client" -EE -w 90% -h 90% -T ' sessions ' \
      "$0" --pick "$socket" "$client" "$here"
    ;;
  pick)
    command -v fzf >/dev/null || stop "fzf is not on the tmux server's PATH ($PATH)"
    list=$(rows) || exit 1
    rc=0
    # --sync: an Enter typed ahead finds the rows there. --with-shell: the
    # socket is quoted for bash, and $SHELL may be fish. pos(2): with the
    # client's own row alone it stays on that.
    pick=$(fzf --sync --ansi --reverse --delimiter '\t' --with-nth 2 --tiebreak index \
      --prompt 'session> ' --with-shell "$BASH -c" --preview-window 'down,70%' \
      --preview "tmux -S $(printf '%q' "$socket") capture-pane -ep -t {1}" \
      --bind 'start:pos(2)' <<<"$list") || rc=$?
    case $rc in
      0)
        target=${pick%%$'\t'*}
        tmux -S "$socket" switch-client -c "$client" -t "$target"
        event_log_note tmux_hooks "$who: -> $(tmux -S "$socket" display-message -p -t "$target" '#{session_name}:#{window_index}')"
        ;;
      # No row matched at Enter, or Esc.
      1 | 130) event_log_note tmux_hooks "$who: closed, nothing picked" ;;
      *) stop "fzf exit $rc" ;;
    esac
    ;;
esac

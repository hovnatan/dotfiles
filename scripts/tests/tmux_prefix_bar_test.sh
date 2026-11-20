#!/usr/bin/env bash
#
# tmux_prefix_bar_test.sh -- the bar's right part, from the title to the
# zone, is drawn reversed while the prefix waits for its key, and only then;
# the current window's tab is not (the status-right line of
# home/.config/tmux/tmux.conf). Two throwaway tmux servers and a throwaway
# HOME, so no live session is touched; about 3 s.
#
#   outer server (-f /dev/null): stands in for the terminal, 120 columns
#     its one pane runs a client of
#   inner server (-f /dev/null + five lines of tmux.conf: @bell_held,
#     @bell_marker, status-right, status-right-length,
#     window-status-current-style)
#     session t, window "tab", prefix C-b (tmux's default),
#     title "(box) [t]", status-stats.sh stood in for: "cpu  1%  mem  2%"
#
#   keys go in with the outer's send-keys, and the inner's bar is read back
#   off the outer's pane, attributes included (capture-pane -e). With <R>
#   where reverse starts, <N> where it would end, and every colour dropped,
#   the bar's row is:
#
#     nothing pressed   [t] 0:tab*        (box) [t]   cpu  1%  mem  2%   19 Nov 12:58 EST
#     C-b               [t] 0:tab*    <R> (box) [t]   cpu  1%  mem  2%   19 Nov 12:58 EST
#     Escape (unbound)  as nothing pressed: the prefix took its key
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

command -v tmux >/dev/null || {
  echo "tmux_prefix_bar_test.sh: tmux not on PATH" >&2
  exit 1
}

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
CONF="$REPO/home/.config/tmux/tmux.conf"
WORK=$(mktemp -d)
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/pfxtest.XXXXXX)
TMUX_BIN=$(command -v tmux)
ESC=$'\033'

# Both servers get an empty environment: no TMUX to refuse the nesting, and
# nothing of the machine's own config.
clean() { env -i HOME="$WORK" PATH=/usr/bin:/bin SHELL=/bin/sh TERM=xterm-256color "$@"; }
outer() { clean "$TMUX_BIN" -S "$SOCKDIR/outer" "$@"; }
inner() { clean "$TMUX_BIN" -S "$SOCKDIR/inner" "$@"; }

cleanup() {
  inner kill-server 2>/dev/null
  outer kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  drop_work
}
trap cleanup EXIT

# --- the lines under test -----------------------------------------------------

grep -E '^set-option -g (@bell_held|@bell_marker|status-right|status-right-length|window-status-current-style) ' \
  "$CONF" >"$WORK/bar.conf"
if [ "$(wc -l <"$WORK/bar.conf")" -eq 5 ]; then
  pass "tmux.conf has the five lines: the marker and its rule, status-right, its length, the tab's style"
else
  fail "tmux.conf: expected five lines, got: $(cat "$WORK/bar.conf")"
fi

# status-right runs ~/.dotfiles/home/.config/tmux/status-stats.sh: the
# throwaway HOME gets one that needs no tmux-mem-cpu-load.
mkdir -p "$WORK/.dotfiles/home/.config/tmux"
printf '#!/bin/sh\necho "cpu  1%%  mem  2%%"\n' >"$WORK/.dotfiles/home/.config/tmux/status-stats.sh"
chmod +x "$WORK/.dotfiles/home/.config/tmux/status-stats.sh"

# --- the two servers ----------------------------------------------------------

inner -f /dev/null new-session -d -s t -n tab -x 120 -y 6
inner set-option -g set-titles-string '(box) [t]'
if inner source-file "$WORK/bar.conf" 2>"$WORK/out"; then
  pass "$("$TMUX_BIN" -V) takes the lines"
else
  fail "$("$TMUX_BIN" -V) refused the lines: $(cat "$WORK/out")"
fi
attach=$(printf '%q ' env -i HOME="$WORK" PATH=/usr/bin:/bin TERM=xterm-256color \
  "$TMUX_BIN" -S "$SOCKDIR/inner" attach-session -t '=t')
outer -f /dev/null new-session -d -x 120 -y 6 "$attach"

# The inner bar as the outer's pane shows it: the row holding the tab's
# label, <R> where reverse is switched on, <N> where it or everything is
# switched off (SGR 27, 0 or none), the other colours dropped.
bar_row() {
  outer capture-pane -e -p | grep -F '0:tab' \
    | sed -E "s/${ESC}\\[7m/<R>/g; s/${ESC}\\[(0|27)?m/<N>/g; s/${ESC}\\[[0-9;]*m//g"
}

# The right part as the stand-ins make it, up to the clock, which is the
# real one. No <R> may come anywhere else (not on the tab), and no <N> at
# all: once on, reverse runs to the end of the row.
RIGHT='\(box\) \[t\]   cpu  1%  mem  2%   [^<]*'
PLAIN="^[^<]*0:tab[^<]* $RIGHT\$"
REVERSED="^[^<]*0:tab[^<]*<R> $RIGHT\$"

# expect <regex> <what>: the bar's row matches within 5 s. It is polled: the
# client attaches, the stats arrive from a background job, and the bar
# redraws after a key, each a moment after the command that caused it.
expect() {
  local want=$1 what=$2 row=""
  for _ in $(seq 50); do
    row=$(bar_row)
    [[ $row =~ $want ]] && break
    sleep 0.1
  done
  if [[ $row =~ $want ]]; then
    pass "$what"
  else
    fail "$what: the bar's row is '$row'"
  fi
}

# --- the bar, before, during and after the prefix --------------------------------

expect "$PLAIN" "nothing pressed: no part of the bar is reversed"

outer send-keys C-b
expect "$REVERSED" "prefix pressed: reversed from the space before the title to the end, the tab not"

# Escape is bound to nothing in the prefix table: the prefix is used up and
# the client is back in the root table.
outer send-keys Escape
expect "$PLAIN" "the next key pressed: no part of the bar is reversed"

finish

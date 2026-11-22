#!/usr/bin/env bash
#
# tmux_extrakto_test.sh -- end-to-end check of prefix Tab, the vendored
# extrakto: its lines of home/.config/tmux/tmux.conf in a throwaway tmux server and
# HOME, pressed by a client in a pty as a terminal sends the keys, with
# extrakto's fzf running in the popup. Needs tmux, fzf and python3; ~10 s.
#
#   session a, window 0   pane %0: prints "alpha reconcile_ledger.py beta"
#                         pane %1: a `cat`, so what lands in it shows on
#                                  its cursor line; the key is pressed here
#              window 1   pane %2: prints "window_two_marker.py"
#   session b             pane %3: prints "session_two_marker.py"
#
# The picker opens on the session's panes (@extrakto_grab_area).
#
#   C-a Tab, "reconc", Enter -> %1 reads "reconcile_ledger.py": a word from
#                               the other pane, inserted at the cursor
#   C-a Tab, "alpha", Tab    -> tmux's buffer holds "alpha" (the copy, by
#                               tmux_osc52), %1 untouched
#
# and of the local changes to it (its .upstream). @extrakto_extra_command is
# a command run for each pane taken, whose output is offered with the panes'
# text. tmux.conf's own is claude-transcript.sh, which says nothing for these
# panes, no claude in them; a stand-in set in its place prints words no pane
# holds, one of them naming the pane it was run for. Ctrl-g switches the
# area taken between the server's panes and the session's
# (@extrakto_grab_area_order).
#
#   C-a Tab, "ledger_arch", Enter      -> %1 reads "ledger_archive.py" right
#                                         after what it held; the stand-in
#                                         was run for %0 %1 %2, with 2000,
#                                         the lines taken of a pane
#   C-a Tab, "window_two", Enter       -> a word of %2, another window's
#   C-a Tab, C-g, "session_two", Enter -> server full: a word of %3, and the
#                                         stand-in was run for %3 too
#   C-a Tab, C-g C-g, "pane0_n", Enter -> the session again: the stand-in's
#                                         word for %0, and it was run once a
#                                         pane, not at each area
#
# and that local.patch beside the vendored copy is those changes as they are
# in the tree.
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux fzf python3; do
  command -v "$cmd" >/dev/null || {
    echo "tmux_extrakto_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/extraktotest.XXXXXX)
SOCK="$SOCKDIR/default"
TMUX_BIN=$(command -v tmux)
# extrakto runs from the server's PATH: this tmux (a distro one found first
# cannot talk to this server, see tmux_hooks_test.sh), fzf and python3.
SERVER_PATH="$(dirname "$TMUX_BIN"):$(dirname "$(command -v fzf)"):$(dirname "$(command -v python3)"):/usr/bin:/bin"

cleanup() {
  [ -n "${client:-}" ] && kill "$client" 2>/dev/null
  t kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  drop_work
}
trap cleanup EXIT

# The throwaway HOME holds the repo at ~/.dotfiles, where the run-shell line
# expects extrakto.
mkdir -p "$H/.dotfiles"
ln -s "$REPO/home" "$H/.dotfiles/home"
t() { env -i HOME="$H" PATH="$SERVER_PATH" TERM=xterm-256color "$TMUX_BIN" -S "$SOCK" "$@"; }
# cursor_line: pane %1's line under its cursor, trailing blanks cut
cursor_line() {
  local y
  y=$(t display-message -p -t %1 '#{cursor_y}')
  t capture-pane -p -t %1 -S "$y" -E "$y" | sed 's/ *$//'
}
line_is() { [ "$(cursor_line)" = "$1" ]; }
# The test's picker runs fzf by this path, to tell it from a picker open in
# a live session: beside one, every pick here waited for that one to close.
FZF="$WORK/fzf"
ln -s "$(command -v fzf)" "$FZF"
fzf_gone() { ! pgrep -f "$FZF --multi --print-query" >/dev/null; }
# area_up <area>: extrakto's fzf runs in the popup, with that grab area in
# its header; a beat more for it to read keys
area_up() { pgrep -f "$FZF --multi --print-query.*1m$1" >/dev/null && sleep 0.3; }
# press <keys>: what the terminal sends, in Python escapes (pty_client.py)
press() { printf '%s\n' "$1" >"$WORK/keys"; }
# pick <query> <key> [area...]: prefix Tab once no popup is up, Ctrl-g for
# each area named, which the picker is then to show, the query typed into
# extrakto's fzf, then the key
pick() {
  local query=$1 key=$2 area
  shift 2
  until_ok 5 fzf_gone || return 1
  press '\001\t'
  until_ok 5 area_up 'session full' || return 1
  for area in "$@"; do
    press '\007'
    until_ok 5 area_up "$area" || return 1
  done
  press "$query"
  sleep 0.3
  press "$key"
}

grep -E '^(set-option -g prefix |set-option -g @extrakto_|run-shell .*/extrakto\.tmux)' \
  "$REPO/home/.config/tmux/tmux.conf" >"$WORK/extrakto.conf"
t -f /dev/null new-session -d -s a -x 120 -y 40 "printf 'alpha reconcile_ledger.py beta\n'; sleep 300"
t set-option -g @extrakto_fzf_tool "$FZF"
t split-window -t a "exec cat"
t new-window -d -t a: "printf 'window_two_marker.py\n'; sleep 300"
t new-session -d -s b "printf 'session_two_marker.py\n'; sleep 300"
# tab_bound: extrakto.tmux's bind-key has run (run-shell may finish after
# source-file returns; `list-keys -T prefix Tab` prints nothing on 3.7c)
tab_bound() { t list-keys -T prefix | grep -qE '^bind-key +-T prefix Tab .*extrakto/scripts/open\.sh'; }
if t source-file "$WORK/extrakto.conf" 2>"$WORK/out" && until_ok 5 tab_bound; then
  pass "$("$TMUX_BIN" -V) loads extrakto from home/.config/tmux/tmux.conf: prefix Tab is bound"
else
  fail "extrakto not loaded: $(cat "$WORK/extrakto.conf" "$WORK/out")"
fi

# --- the client -------------------------------------------------------------------

# A 120x40 terminal on a, sent each line written to the fifo as the keys it
# spells.
mkfifo "$WORK/keys"
python3 "$PTY_CLIENT" "$TMUX_BIN" "$SOCK" "$H" a --keys "$WORK/keys" --path "$SERVER_PATH" --size 40x120 &
client=$!
attached() { [ -n "$(t list-clients -F x)" ]; }
until_ok 5 attached || fail "the client never attached"

# --- insert and copy --------------------------------------------------------------

if pick reconc '\r'; then
  until_ok 5 line_is reconcile_ledger.py \
    && pass "Enter inserts a word from the other pane at the cursor" \
    || fail "after reconc Enter, %1 reads '$(cursor_line)'"
else
  fail "no extrakto fzf after C-a Tab"
fi

buffer_is() { [ "$(t show-buffer 2>/dev/null)" = "$1" ]; }
if pick alpha '\t'; then
  until_ok 5 buffer_is alpha \
    && line_is reconcile_ledger.py \
    && pass "Tab copies the pick to tmux's buffer and leaves the pane alone" \
    || fail "after alpha Tab, buffer '$(t show-buffer 2>&1)', %1 '$(cursor_line)'"
else
  fail "no extrakto fzf for the copy"
fi

# --- text from outside the panes --------------------------------------------------

cat >"$WORK/extra.sh" <<EOF
#!/bin/sh
echo "\$*" >>"$WORK/extra.args"
echo "delta ledger_archive.py pane\${1#%}_notes.md"
EOF
chmod +x "$WORK/extra.sh"
t set-option -g @extrakto_extra_command "$WORK/extra.sh"
# ran_for: the panes the stand-in was run for since the file was emptied,
# one entry a run
ran_for() { sort "$WORK/extra.args" | paste -sd, -; }
held=reconcile_ledger.py
# offered <what> <query> <word> <runs> [area...]: the word is inserted, and
# the stand-in was run for just those panes
offered() {
  local what=$1 query=$2 word=$3 runs=$4
  shift 4
  : >"$WORK/extra.args"
  if pick "$query" '\r' "$@"; then
    held=$held$word
    until_ok 5 line_is "$held" && [ "$(ran_for)" = "$runs" ] && pass "$what" \
      || fail "$what: %1 reads '$(cursor_line)', wanted '$held'; the command was run for '$(ran_for)', wanted '$runs'"
  else
    fail "$what: no extrakto fzf showing ${*:-session full}"
  fi
}
offered "a word of @extrakto_extra_command's output is offered and inserted; the command is run for each pane of the session, with the lines taken of one" \
  ledger_arch ledger_archive.py '%0 2000,%1 2000,%2 2000'

# --- the areas ----------------------------------------------------------------------

offered "the picker opens on the session: a word of another window's pane" \
  window_two window_two_marker.py '%0 2000,%1 2000,%2 2000'
offered "Ctrl-g, server full: a word of another session's pane, and the command is run for it too" \
  session_two session_two_marker.py '%0 2000,%1 2000,%2 2000,%3 2000' 'server full'
offered "Ctrl-g twice, the session again: the command's word for another pane; it is run once a pane, not again at each area" \
  pane0_n pane0_notes.md '%0 2000,%1 2000,%2 2000,%3 2000' 'server full' 'session full'

# A bump re-copies upstream's files and applies the patch, so the patch has
# to be the change that is in the tree.
vendor=home/.config/tmux/vendor/extrakto
if out=$(git -C "$REPO" apply --check -R "$vendor/local.patch" 2>&1); then
  pass "local.patch comes off the vendored extrakto cleanly"
else
  fail "local.patch is not the vendored extrakto's local change: $out"
fi

finish

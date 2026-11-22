#!/usr/bin/env bash
#
# tmux_extrakto_test.sh -- end-to-end check of prefix Tab, the vendored
# extrakto: its lines of home/.config/tmux/tmux.conf in a throwaway tmux server and
# HOME, pressed by a client in a pty as a terminal sends the keys, with
# extrakto's fzf running in the popup. Needs tmux, fzf and python3; ~5 s.
#
#   pane %0: prints "alpha reconcile_ledger.py beta"
#   pane %1: a `cat`, so what lands in it shows on its cursor line
#
#   C-a Tab, "reconc", Enter -> %1 reads "reconcile_ledger.py": a word from
#                               the other pane, inserted at the cursor
#   C-a Tab, "alpha", Tab    -> tmux's buffer holds "alpha" (the copy, by
#                               tmux_osc52), %1 untouched
#
# and of @extrakto_extra_command, the local change to it (its .upstream): a
# command whose output is offered with the panes' text. tmux.conf's own is
# claude-transcript.sh, which says nothing for these panes, no claude in
# them; a stand-in set in its place prints a word no pane holds.
#
#   C-a Tab, "ledger_arch", Enter -> %1 reads "ledger_archive.py" right after
#                                    what it held, and the stand-in was run
#                                    with %1, the pane the key was pressed
#                                    in, and 2000, the lines taken of a pane
#
# and that local.patch beside the vendored copy is that change as it is in
# the tree.
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
# fzf_up: extrakto's fzf runs in the popup; a beat more for it to read keys
fzf_up() { pgrep -f 'fzf --multi --print-query' >/dev/null && sleep 0.3; }
fzf_gone() { ! pgrep -f 'fzf --multi --print-query' >/dev/null; }
# press <keys>: what the terminal sends, in Python escapes (pty_client.py)
press() { printf '%s\n' "$1" >"$WORK/keys"; }
# pick <query> <key>: prefix Tab once no popup is up, the query typed into
# extrakto's fzf, then the key
pick() {
  until_ok 5 fzf_gone || return 1
  press '\001\t'
  until_ok 5 fzf_up || return 1
  press "$1"
  sleep 0.3
  press "$2"
}

grep -E '^(set-option -g prefix |set-option -g @extrakto_|run-shell .*/extrakto\.tmux)' \
  "$REPO/home/.config/tmux/tmux.conf" >"$WORK/extrakto.conf"
t -f /dev/null new-session -d -s a -x 120 -y 40 "printf 'alpha reconcile_ledger.py beta\n'; sleep 300"
t split-window -t a "exec cat"
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
echo "\$*" >"$WORK/extra.args"
echo "delta ledger_archive.py"
EOF
chmod +x "$WORK/extra.sh"
t set-option -g @extrakto_extra_command "$WORK/extra.sh"
if pick ledger_arch '\r'; then
  until_ok 5 line_is reconcile_ledger.pyledger_archive.py \
    && [ "$(cat "$WORK/extra.args")" = "%1 2000" ] \
    && pass "a word of @extrakto_extra_command's output is offered and inserted; the command is run with the pane and the lines taken of one" \
    || fail "after ledger_arch Enter, %1 reads '$(cursor_line)', the command was run with '$(cat "$WORK/extra.args" 2>&1)'"
else
  fail "no extrakto fzf with @extrakto_extra_command set"
fi

# A bump re-copies upstream's files and applies the patch, so the patch has
# to be the change that is in the tree.
vendor=home/.config/tmux/vendor/extrakto
if out=$(git -C "$REPO" apply --check -R "$vendor/local.patch" 2>&1); then
  pass "local.patch comes off the vendored extrakto cleanly"
else
  fail "local.patch is not the vendored extrakto's local change: $out"
fi

finish

#!/usr/bin/env bash
# check.sh covers: home/.tmux.conf home/.config/tmux/vendor/extrakto/*
#
# tmux_extrakto_test.sh -- end-to-end check of prefix Tab, the vendored
# extrakto: its lines of home/.tmux.conf in a throwaway tmux server and
# HOME, pressed by a client in a pty as a terminal sends the keys, with
# extrakto's fzf running in the popup. Needs tmux, fzf and python3; ~5 s.
#
#   pane %0: prints "alpha reconcile_ledger.py beta"
#   pane %1: a `cat`, so what lands in it shows on its cursor line
#
#   C-a Tab, "reconc", Tab   -> %1 reads "reconcile_ledger.py": a word from
#                               the other pane, inserted at the cursor
#   C-a Tab, "alpha", Enter  -> tmux's buffer holds "alpha" (the copy, by
#                               tmux_osc52), %1 untouched
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux fzf python3; do
  command -v "$cmd" >/dev/null || {
    echo "tmux_extrakto_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/extraktotest.XXXXXX)
SOCK="$SOCKDIR/default"
TMUX_BIN=$(command -v tmux)
# extrakto runs from the server's PATH: this tmux (a distro one found first
# cannot talk to this server, see tmux_hooks_test.sh), fzf and python3.
SERVER_PATH="$(dirname "$TMUX_BIN"):$(dirname "$(command -v fzf)"):$(dirname "$(command -v python3)"):/usr/bin:/bin"

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
cleanup() {
  [ -n "${client:-}" ] && kill "$client" 2>/dev/null
  t kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
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
# until_ok <seconds> <command...>: retry the command every 0.1 s until it passes
until_ok() {
  local n=$(($1 * 10))
  shift
  for _ in $(seq "$n"); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}
line_is() { [ "$(cursor_line)" = "$1" ]; }
# fzf_up: extrakto's fzf runs in the popup; a beat more for it to read keys
fzf_up() { pgrep -f 'fzf --multi --print-query' >/dev/null && sleep 0.3; }
# press <bytes>: what the terminal sends, written into the client's pty
press() { printf '%b' "$1" >"$WORK/keys"; }

grep -E '^(set-option -g prefix |set-option -g @extrakto_|run-shell .*/extrakto\.tmux)' \
  "$REPO/home/.tmux.conf" >"$WORK/extrakto.conf"
t -f /dev/null new-session -d -s a -x 120 -y 40 "printf 'alpha reconcile_ledger.py beta\n'; sleep 300"
t split-window -t a "exec cat"
# tab_bound: extrakto.tmux's bind-key has run (run-shell may finish after
# source-file returns; `list-keys -T prefix Tab` prints nothing on 3.7c)
tab_bound() { t list-keys -T prefix | grep -qE '^bind-key +-T prefix Tab .*extrakto/scripts/open\.sh'; }
if t source-file "$WORK/extrakto.conf" 2>"$WORK/out" && until_ok 5 tab_bound; then
  pass "$("$TMUX_BIN" -V) loads extrakto from home/.tmux.conf: prefix Tab is bound"
else
  fail "extrakto not loaded: $(cat "$WORK/extrakto.conf" "$WORK/out")"
fi

# --- the client -------------------------------------------------------------------

# Attaches to a in a 120x40 pty and writes whatever arrives on the fifo into
# it, as keystrokes; then stays until killed.
mkfifo "$WORK/keys"
python3 - "$TMUX_BIN" "$SOCK" "$H" "$SERVER_PATH" "$WORK/keys" <<'PYEOF' &
import fcntl, os, pty, select, struct, sys, termios
tmux, sock, home, path, keys = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    os.execve(tmux, [tmux, "-S", sock, "attach", "-t", "=a"], {"HOME": home, "PATH": path, "TERM": "xterm-256color"})
fifo = os.open(keys, os.O_RDWR)
while True:
    ready = select.select([fd, fifo], [], [])[0]
    if fifo in ready:
        os.write(fd, os.read(fifo, 4096))
    if fd in ready:
        try: os.read(fd, 65536)
        except OSError: break
PYEOF
client=$!
attached() { [ -n "$(t list-clients -F x)" ]; }
until_ok 5 attached || fail "the client never attached"

# --- insert and copy --------------------------------------------------------------

press '\001\t'
if until_ok 5 fzf_up; then
  press 'reconc'
  sleep 0.3
  press '\t'
  until_ok 5 line_is reconcile_ledger.py \
    && pass "Tab inserts a word from the other pane at the cursor" \
    || fail "after reconc Tab, %1 reads '$(cursor_line)'"
else
  fail "no extrakto fzf after C-a Tab"
fi

fzf_gone() { ! pgrep -f 'fzf --multi --print-query' >/dev/null; }
buffer_is() { [ "$(t show-buffer 2>/dev/null)" = "$1" ]; }
until_ok 5 fzf_gone || fail "the first popup never closed"
press '\001\t'
if until_ok 5 fzf_up; then
  press 'alpha'
  sleep 0.3
  press '\r'
  until_ok 5 buffer_is alpha \
    && line_is reconcile_ledger.py \
    && pass "Enter copies the pick to tmux's buffer and leaves the pane alone" \
    || fail "after alpha Enter, buffer '$(t show-buffer 2>&1)', %1 '$(cursor_line)'"
else
  fail "no extrakto fzf for the copy"
fi

[ "$failures" -eq 0 ] && log "all passed" || log "$failures failed"
[ "$failures" -eq 0 ]

#!/usr/bin/env bash
#
# tmux_thumbs_test.sh -- end-to-end check of prefix f, tmux-thumbs
# (nix/flake.nix): its lines of home/.config/tmux/tmux.conf in a throwaway
# tmux server and HOME, pressed by a client in a pty as a terminal sends the
# keys. Needs tmux, python3 and tmux-thumbs in ~/.nix-profile; ~5 s.
#
#   pane %0: prints a git SHA and a URL, then runs `cat` so what is pasted
#            shows on the cursor line
#
#   C-a f, a   lowercase hint -> pastes the match at the cursor
#   C-a f, S   uppercase hint -> copies the match to tmux's buffer (OSC 52)
#              and leaves the pane untouched
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux python3; do
  command -v "$cmd" >/dev/null || {
    echo "tmux_thumbs_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done
THUMBS_SH="$HOME/.nix-profile/share/tmux-plugins/tmux-thumbs/tmux-thumbs.sh"
[ -x "$THUMBS_SH" ] || {
  echo "tmux_thumbs_test.sh: $THUMBS_SH missing; it comes from nix/flake.nix (nix profile upgrade nix)" >&2
  exit 1
}

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/thumbstest.XXXXXX)
SOCK="$SOCKDIR/default"
TMUX_BIN=$(command -v tmux)
SERVER_PATH="$(dirname "$TMUX_BIN"):$(dirname "$(command -v bash)"):/usr/bin:/bin"

cleanup() {
  [ -n "${client:-}" ] && kill "$client" 2>/dev/null
  t kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  drop_work
}
trap cleanup EXIT

mkdir -p "$H"
ln -s "$HOME/.nix-profile" "$H/.nix-profile"
t() { env -i HOME="$H" PATH="$SERVER_PATH" TERM=xterm-256color "$TMUX_BIN" -S "$SOCK" "$@"; }

cursor_line() {
  local y
  y=$(t display-message -p -t %0 '#{cursor_y}')
  t capture-pane -p -t %0 -S "$y" -E "$y" | sed 's/ *$//'
}
line_is() { [ "$(cursor_line)" = "$1" ]; }
buffer_is() { [ "$(t show-buffer 2>/dev/null)" = "$1" ]; }
thumbs_up() { t list-windows -F '#{window_name}' | grep -qx '\[thumbs\]'; }
thumbs_gone() { ! thumbs_up; }
press() { printf '%s\n' "$1" >"$WORK/keys"; }

grep -E '^(set-option -g prefix |set-option -g @thumbs-|bind-key f )' \
  "$REPO/home/.config/tmux/tmux.conf" >"$WORK/thumbs.conf"

# Two distinct matches in reverse order (@thumbs-reverse): the bottom line
# gets hint 'a' (near the prompt) and the top line gets 's' (qwerty).
SHA="deadbeef1234567890abcdef1234567890abcdef"
URL="https://example.com/thumbs-check"
t -f /dev/null new-session -d -s a -x 120 -y 30 \
  "printf '%s\n%s\n' '$URL' '$SHA'; exec cat"

if t source-file "$WORK/thumbs.conf" 2>"$WORK/out" \
  && t list-keys -T prefix | grep -qE '^bind-key +-T prefix f .*tmux-thumbs\.sh'; then
  pass "$("$TMUX_BIN" -V) loads tmux-thumbs from home/.config/tmux/tmux.conf: prefix f is bound"
else
  fail "tmux-thumbs not loaded: $(cat "$WORK/thumbs.conf" "$WORK/out")"
fi

mkfifo "$WORK/keys"
python3 "$PTY_CLIENT" "$TMUX_BIN" "$SOCK" "$H" a --keys "$WORK/keys" --path "$SERVER_PATH" --size 30x120 &
client=$!
attached() { [ -n "$(t list-clients -F x)" ]; }
until_ok 5 attached || fail "the client never attached"
pane_ready() { t capture-pane -p -t %0 | grep -qF "$SHA"; }
until_ok 5 pane_ready || fail "pane never printed its test lines"

# Lowercase 'a': pastes the nearest match (the SHA) at the cursor.
press '\001f'
if until_ok 5 thumbs_up; then
  sleep 0.2
  press 'a'
  if until_ok 5 thumbs_gone && until_ok 5 line_is "$SHA"; then
    pass "lowercase hint pastes the match at the cursor"
  else
    fail "after C-a f a, cursor line is '$(cursor_line)', buffer is '$(t show-buffer 2>&1)'"
  fi
else
  fail "no [thumbs] window after C-a f"
fi

# Uppercase 'S': with @thumbs-unique enabled, the two copies of $SHA share
# hint 'a', so the URL above them still takes the second qwerty letter 's'.
press '\001f'
if until_ok 5 thumbs_up; then
  sleep 0.2
  press 'S'
  if until_ok 5 thumbs_gone && until_ok 5 buffer_is "$URL" && line_is "$SHA"; then
    pass "uppercase hint copies the match to tmux's buffer and leaves the pane alone"
  else
    fail "after C-a f S, buffer is '$(t show-buffer 2>&1)', cursor line is '$(cursor_line)'"
  fi
else
  fail "no [thumbs] window for uppercase copy"
fi

finish

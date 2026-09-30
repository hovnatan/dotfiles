#!/usr/bin/env bash
#
# tmux_hooks_test.sh -- end-to-end checks for the tmux hooks' log: the hook
# lines of home/.tmux.conf and the scripts they run, in a throwaway tmux
# server and HOME, with a client in a pty that reports focus as a terminal
# does. Needs tmux (3.6 or later, for the focus hooks) and python3; about
# 15 s.
#
#   sessions   a: sleep           b: a stand-in "claude" (a link to sleep,
#                                    which is all focus-out-unattached.sh
#                                    looks at: the name and the foreground)
#
#   client attaches to a                  -> attached ... session=a
#   a bystander client attaches to b, and reports nothing
#   reports focus in, out, in             -> focus-in, focus-out, focus-in,
#                                            each naming this client's tty,
#                                            not the bystander's (the format
#                                            client_tty named whichever
#                                            client tmux had last, so every
#                                            line of two tabs read the same)
#   switch-client to b                    -> session-changed ... session=b
#   a's pane title "* <host>-renamed"     -> session $N renamed a -> renamed
#   client dies                           -> detached ... session=b
#                                            synthetic focus-out to %N (b)
#
# The socket is named "claude": sync-session-name.sh acts on that one only.
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux python3; do
  command -v "$cmd" >/dev/null || { echo "tmux_hooks_test.sh: $cmd not on PATH" >&2; exit 1; }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/hooktest.XXXXXX)
SOCK="$SOCKDIR/claude"
TMUX_BIN=$(command -v tmux)

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() { log "FAIL $*"; failures=$((failures + 1)); }
cleanup() {
  [ -n "${client:-}" ] && kill "$client" 2>/dev/null
  [ -n "${bystander:-}" ] && kill "$bystander" 2>/dev/null
  t kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# The throwaway HOME holds the repo at ~/.dotfiles, where the hook lines
# expect their scripts; the logs land in its .logs, not the checkout's. The
# server's PATH is the system's plus tmux's own directory, for the scripts.
mkdir -p "$H/.dotfiles"
ln -s "$REPO/home" "$H/.dotfiles/home"
ln -s "$REPO/scripts" "$H/.dotfiles/scripts"
t() { env -i HOME="$H" PATH="/usr/bin:/bin:$(dirname "$TMUX_BIN")" TERM=xterm-256color "$TMUX_BIN" -S "$SOCK" "$@"; }
hooks_log() { cat "$H"/.dotfiles/.logs/*_tmux_hooks/events.log 2>/dev/null; }
# wait_for <pattern>: until the log has a line matching it, 5 s at most
wait_for() {
  for _ in $(seq 50); do hooks_log | grep -q -E -- "$1" && return 0; sleep 0.1; done
  return 1
}

ln -s /bin/sleep "$WORK/claude"
grep -E '^set-hook -g (client-(attached|detached|session-changed|focus-in|focus-out)|pane-title-changed)' \
  "$REPO/home/.tmux.conf" > "$WORK/hooks.conf"
t -f /dev/null new-session -d -s a 'sleep 300'
t new-session -d -s b "$WORK/claude 300"
t set -g focus-events on
if t source-file "$WORK/hooks.conf" 2> "$WORK/out"; then
  pass "$("$TMUX_BIN" -V) takes the $(wc -l < "$WORK/hooks.conf" | tr -d ' ') hook lines of home/.tmux.conf"
else
  fail "hook lines refused: $(cat "$WORK/out")"
fi

# --- the clients ------------------------------------------------------------------

# Attaches to a and, once the bystander is there too, reports focus in, out,
# in, a second apart, as a terminal with focus reporting on does; then stays
# until killed.
python3 - "$TMUX_BIN" "$SOCK" "$H" <<'PYEOF' &
import os, pty, select, sys, time
tmux, sock, home = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execve(tmux, [tmux, "-S", sock, "attach", "-t", "=a"], {"HOME": home, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color"})
start = time.time(); todo = [(3.0, b"\x1b[I"), (4.0, b"\x1b[O"), (5.0, b"\x1b[I")]
while True:
    if todo and time.time() - start >= todo[0][0]:
        os.write(fd, todo.pop(0)[1])
    if select.select([fd], [], [], 0.05)[0]:
        try: os.read(fd, 65536)
        except OSError: break
PYEOF
client=$!

wait_for ' attached [^ ]+ session=a: not iTerm2, local: @ssh unset$' \
  && pass "attach is logged, with what was reported" || fail "no attach line: $(hooks_log)"
client_tty=$(t list-clients -t =a -F '#{client_tty}')
# A bystander on b that never reports focus, attached after the client under
# test: it is then the client tmux had last, which is the one a wrong format
# names. With a single client, or with the bystander first, every format
# names the right one.
python3 - "$TMUX_BIN" "$SOCK" "$H" <<'PYEOF' &
import os, pty, sys
tmux, sock, home = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execve(tmux, [tmux, "-S", sock, "attach", "-t", "=b"], {"HOME": home, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color"})
while True:
    try:
        if not os.read(fd, 65536): break
    except OSError: break
PYEOF
bystander=$!
for _ in $(seq 50); do [ -n "$(t list-clients -t =b -F '#{client_tty}')" ] && break; sleep 0.1; done
bystander_tty=$(t list-clients -t =b -F '#{client_tty}')

wait_for ' focus-in [^ ]+ session=a$' || true
sleep 3
focus=$(hooks_log | sed -n -E 's/.* (focus-(in|out)) [^ ]+ session=a$/\1/p' | tr '\n' ' ')
case "$focus" in
  *"focus-in focus-out focus-in ") pass "focus in, out, in are logged in order ($focus)" ;;
  *) fail "focus lines: '$focus'" ;;
esac
wrong=$(hooks_log | grep -E 'Z focus-(in|out) ' | grep -c -v -F " $client_tty session=a")
[ "$wrong" = 0 ] && [ "$client_tty" != "$bystander_tty" ] \
  && pass "each names the client that reported it ($client_tty, not the bystander $bystander_tty)" \
  || fail "$wrong focus line(s) name another client than $client_tty: $(hooks_log | grep -E 'Z focus-(in|out) ')"

# --- session switch, rename, detach -------------------------------------------------

t switch-client -c "$client_tty" -t b
wait_for ' session-changed [^ ]+ session=b: not iTerm2, local: @ssh unset$' \
  && pass "a session switch is logged" || fail "no session-changed line: $(hooks_log)"

t select-pane -t a -T "* $HOSTNAME-renamed"
wait_for " session \\\$[0-9]+ renamed a -> renamed \\(pane title \"\\* $HOSTNAME-renamed\"\\)\$" \
  && pass "a rename from the pane title is logged" || fail "no rename line: $(hooks_log)"
[ "$(t list-sessions -F '#{session_name}' | sort | tr '\n' ' ')" = "b renamed " ] \
  && pass "and the session is renamed" || fail "sessions: $(t list-sessions -F '#{session_name}' | tr '\n' ' ')"

# wait: without it bash prints the killed job, heredoc and all.
kill "$client"; wait "$client" 2>/dev/null; client=
wait_for " detached $client_tty session=b\$" && pass "the detach is logged, naming the client" || fail "no detached line: $(hooks_log)"
# b keeps its bystander until now: only with it gone is the claude pane
# without a client.
kill "$bystander"; wait "$bystander" 2>/dev/null; bystander=
wait_for ' synthetic focus-out to %[0-9]+ \(b\): no client attached$' \
  && pass "the focus-out sent to the clientless claude pane is logged" || fail "no synthetic focus-out line: $(hooks_log)"

# --- the log as a whole ---------------------------------------------------------------

odd=$(hooks_log | grep -c -v -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ')
[ "$odd" = 0 ] && pass "every line is UTC-stamped ($(hooks_log | wc -l | tr -d ' ') lines, one file for all the hooks)" \
  || fail "$odd line(s) without a UTC stamp"

log "$failures failure(s)"
[ "$failures" -eq 0 ]

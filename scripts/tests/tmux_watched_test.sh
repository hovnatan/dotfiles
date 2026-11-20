#!/usr/bin/env bash
#
# tmux_watched_test.sh -- scripts/tmux_watched.sh against a real tmux: the
# one rule for "somebody is looking", which the session-done mod asks about
# claude's pane (for its ntfy push) and home/.config/tmux/bell-elsewhere.sh
# about a session (for the bell marker). Runs it on a throwaway tmux server,
# with real clients attached in ptys, and reads its exit status and what it
# prints. What the callers do with the answers is theirs to test: the mod's
# hooks/register.test.ts (scripts/tests/claude_mods_test.sh runs it) and
# scripts/tests/tmux_hooks_test.sh. Needs tmux and python3; about 3 s.
#
#   scenario    what is attached                 pane <its first pane>   session
#   nobody      no client                        1 "no client attached"  1
#   watched     a client in a pty, focus-in      0 "<tty> focused, ..."  0
#               sent, on the pane's window
#               of two
#                 with a stale bound of 0        1 "focused, input Ns"   1
#                 after it reports focus-out     1 "not focused, ..."    1
#   elsewhere   a focused client on window 1,    1 "on window 1 (the     0
#               the pane in window 0               pane's is 0)"
#   zoomed      a focused client on the pane's   1 "zoomed onto another  0
#               window, zoomed onto the other      pane"
#               pane of a split
#   moved       the pane's window moved into     0 (a client counts by the
#               another session, where a           window it shows), and
#               focused client shows it            session-name names it
#   panegone    the pane killed, its session     2
#               kept by another window
#   goes        the session killed               2                       2
#   (no server on the socket)                    2                       2
#   tmuxfail    tmux failing (a wrapper on PATH, "protocol version
#               mismatch") -> 3 and "tmux -S <socket>: <the message>" for
#               all three questions: never 2, which a caller reads as
#               nothing left to tell about
#   session-name <pane>  -> the pane's session now; 2 gone; 3 failing
#
# Exit 0 = all passed.

set -uo pipefail

for cmd in tmux python3; do
  command -v "$cmd" >/dev/null || {
    echo "tmux_watched_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"
event_log_start tmux_watched_test --no-prune

WATCH="$REPO/scripts/tmux_watched.sh"
WORK=$(mktemp -d)
# Unix socket paths are capped near 108 bytes, so not under $WORK.
SOCK="/tmp/tmuxwatched-$$.sock"

failures=0
# log prints each line as well as recording it (scripts/lib/event_log.sh).
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
t() { tmux -S "$SOCK" "$@"; }

clients_pids=""
cleanup() {
  for c in $clients_pids; do kill "$c" 2>/dev/null; done
  t kill-server 2>/dev/null
  rm -f "$SOCK"
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- throwaway tmux server ---------------------------------------------------

t -f /dev/null new-session -d -s keepalive 'sleep 1000'
t set -g focus-events on
new_session() { # prints the session id without its "$"
  t new-session -d -s "$1" 'sleep 1000'
  t display -p -t "=$1:" '#{session_id}' | tr -d '$'
}
# pane_of <session id>: the session's first pane, window 0's: the one asked
# about, as claude's is by the mod (its $TMUX_PANE)
pane_of() { t list-panes -t "\$$1:0" -F '#{pane_id}' | head -1; }

# wait_focus <session target> <yes|no>: until a client of the session is
# focused, or none is; 6 s at the most.
wait_focus() {
  local has
  for _ in $(seq 120); do
    has=no
    t list-clients -t "$1" -F '#{client_flags}' 2>/dev/null | grep -q focused && has=yes
    [ "$has" = "$2" ] && return
    sleep 0.05
  done
}

# focused_client <session> [<file>]: a real tmux client in a pty, attached to
# the session; the focus-in sequence it is sent is what a terminal emits when
# its window gains focus, which sets client_flags focused and refreshes
# client_activity -- exactly what the rule tests. When <file> appears it
# sends the focus-out a terminal emits on losing focus. Waits until tmux
# has the client focused (wait_focus); its pid is appended to $clients_pids.
focused_client() {
  python3 - "$SOCK" "$1" "${2:-$WORK/never}" <<'PYEOF' &
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE")} | {"TERM": "xterm-256color"}
    os.execvpe("tmux", ["tmux", "-S", sys.argv[1], "attach", "-t", "=" + sys.argv[2]], env)
time.sleep(1); os.write(fd, b"\x1b[I")
end = time.time() + 60; unfocused = False
while time.time() < end:
    if not unfocused and os.path.exists(sys.argv[3]):
        os.write(fd, b"\x1b[O"); unfocused = True
    if select.select([fd], [], [], 0.1)[0]:
        try: os.read(fd, 65536)
        except OSError: break
PYEOF
  clients_pids+=" $!"
  wait_focus "=$1" yes
}

sid_nobody=$(new_session nobody)
# watched: the pane's window 0 is the current one of two.
sid_watched=$(new_session watched)
t new-window -d -t "=watched:" 'sleep 1000'
focused_client watched "$WORK/unfocus"
# elsewhere: the client is on window 1, a shell beside the pane's.
sid_else=$(new_session elsewhere)
t new-window -t "=elsewhere:" 'sleep 1000'
focused_client elsewhere
# zoomed: the pane's window is current, but zoomed onto its other pane.
sid_zoom=$(new_session zoomed)
t split-window -t "=zoomed:0" 'sleep 1000'
t resize-pane -Z -t "=zoomed:0.1"
focused_client zoomed
# moved: the pane's window 0 moved into another session and made current
# there, a focused client attached to that one; the session it came from
# keeps a second window.
sid_moved=$(new_session movedfrom)
t new-window -d -t "=movedfrom:" 'sleep 1000'
pane_moved=$(pane_of "$sid_moved")
new_session movedto >/dev/null
t move-window -s "=movedfrom:0" -t "=movedto:"
t select-window -t "$(t display -p -t "$pane_moved" '#{window_id}')"
focused_client movedto
sid_panegone=$(new_session panegone)
t new-window -d -t "=panegone:" 'sleep 1000'
pane_gone=$(pane_of "$sid_panegone")
sid_goes=$(new_session goes)
pane_goes=$(pane_of "$sid_goes")

# is <label> <want status> <want output, an extended regex> <tmux_watched.sh args...>
is() {
  local label=$1 want=$2 re=$3 out rc
  shift 3
  out=$("$WATCH" "$@" 2>&1)
  rc=$?
  if [ "$rc" = "$want" ] && [[ "$out" =~ $re ]]; then
    pass "$label: exit $rc${out:+, \"$out\"}"
  else
    fail "$label: exit $rc (want $want), output \"$out\" (want /$re/)"
  fi
}
# pane_is / session_is <label> <want status> <want output> <session id>: the
# question about that session's first pane, or about the session.
pane_is() { is "pane, $1" "$2" "$3" -S "$SOCK" pane "$(pane_of "$4")"; }
session_is() { is "session, $1" "$2" "$3" -S "$SOCK" session "\$$4"; }
TTY='(ttys[0-9]+|pts/[0-9]+)'
SEEN="$TTY focused, input [0-9]+s ago"
MISMATCH="^tmux -S $SOCK: protocol version mismatch \(client 8, server 9\)\$"

# --- pane: is it on somebody's screen ----------------------------------------

pane_is "nobody attached" 1 '^no client attached$' "$sid_nobody"
pane_is "a focused client on its window" 0 "^$SEEN\$" "$sid_watched"
# The freshness bound: focus alone is not believed. With a bound of 0 no
# input is fresh, as none is after the bound on a locked screen.
TMUX_WATCHED_STALE_SECONDS=0 pane_is "focused, but its input is stale" 1 "^$SEEN\$" "$sid_watched"
pane_is "a focused client on another window" 1 "^$SEEN, on window 1 \(the pane's is 0\)\$" "$sid_else"
pane_is "its window zoomed onto another pane" 1 "^$SEEN, the pane's window zoomed onto another pane\$" "$sid_zoom"
is "pane, its window shown in another session by a focused client" 0 "^$SEEN\$" -S "$SOCK" pane "$pane_moved"

# --- session: is anybody on it, at any window --------------------------------

session_is "nobody attached" 1 '^no client attached$' "$sid_nobody"
session_is "a focused client" 0 "^$SEEN\$" "$sid_watched"
TMUX_WATCHED_STALE_SECONDS=0 session_is "focused, but its input is stale" 1 "^$SEEN\$" "$sid_watched"
# The two widths: the client that has not seen the pane is on the session.
session_is "a focused client on another window than the pane's" 0 "^$SEEN\$" "$sid_else"
session_is "a focused client, the window zoomed" 0 "^$SEEN\$" "$sid_zoom"
session_is "the one a window was moved out of" 1 '^no client attached$' "$sid_moved"

# The same client loses focus.
touch "$WORK/unfocus"
wait_focus "\$$sid_watched" no
pane_is "after focus-out" 1 "^$TTY not focused, input [0-9]+s ago\$" "$sid_watched"
session_is "after focus-out" 1 "^$TTY not focused, input [0-9]+s ago\$" "$sid_watched"

# --- session-name ------------------------------------------------------------

is "session-name: where the pane is now" 0 '^movedto$' -S "$SOCK" session-name "$pane_moved"

# --- no -S: the server is the caller's, by $TMUX ------------------------------

# As the mod asks, from inside a pane: tmux reads $TMUX, and nothing else does.
TMUX="$SOCK,$(t display -p '#{pid}'),0" is "pane, the server found by \$TMUX" 0 "^$SEEN\$" pane "$pane_moved"
TMUX="$WORK/nosuch.sock,1,0" is "pane, \$TMUX naming a server that is gone" 2 '^$' pane %0

# --- gone: the pane, the session, the server ---------------------------------

t kill-pane -t "$pane_gone"
is "pane killed, its session kept" 2 '^$' -S "$SOCK" pane "$pane_gone"
is "session-name of a pane that is gone" 2 '^$' -S "$SOCK" session-name "$pane_gone"
t kill-session -t =goes
is "pane, its session killed" 2 '^$' -S "$SOCK" pane "$pane_goes"
is "session killed" 2 '^$' -S "$SOCK" session "\$$sid_goes"
for what in pane session session-name; do
  is "$what with no server on the socket" 2 '^$' -S "$WORK/nosuch.sock" "$what" %0
done

# --- tmux failing is not "gone" ----------------------------------------------

mkdir -p "$WORK/failtmux"
cat >"$WORK/failtmux/tmux" <<'EOF'
#!/bin/sh
echo "protocol version mismatch (client 8, server 9)" >&2
exit 1
EOF
chmod +x "$WORK/failtmux/tmux"
# The pane is asked for before PATH changes: pane_of needs the real tmux.
pane_nobody=$(pane_of "$sid_nobody")
PATH="$WORK/failtmux:$PATH" is "pane, tmux failing" 3 "$MISMATCH" -S "$SOCK" pane "$pane_nobody"
PATH="$WORK/failtmux:$PATH" is "session, tmux failing" 3 "$MISMATCH" -S "$SOCK" session "\$$sid_nobody"
PATH="$WORK/failtmux:$PATH" is "session-name, tmux failing" 3 "$MISMATCH" -S "$SOCK" session-name "$pane_nobody"

# --- asked wrongly -----------------------------------------------------------

is "an unknown question" 64 '^tmux_watched.sh: usage: ' bogus
is "pane with no pane" 64 '^tmux_watched.sh: usage: ' -S "$SOCK" pane
is "a socket and no question" 64 '^tmux_watched.sh: usage: ' -S "$SOCK"

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

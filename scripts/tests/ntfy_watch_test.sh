#!/usr/bin/env bash
# check.sh covers: home/.claude/mods/session-done/tmux-watch.sh
#
# ntfy_watch_test.sh -- home/.claude/mods/session-done/tmux-watch.sh against
# a real tmux: the script the session-done mod asks, for its ntfy push,
# whether claude's pane is being watched. Runs it on a throwaway tmux server,
# with real clients attached in ptys, and reads its exit status and what it
# prints. What the mod does with the answers is hooks/register.test.ts's
# (scripts/tests/claude_mods_test.sh runs it). Needs tmux and python3; about
# 2 s.
#
#   watched <$TMUX> <pane>, per scenario session:
#     nobody      no client attached                -> 1 "no client attached"
#     watched     a client in a pty, focus-in sent, on claude's window of
#                 two                               -> 0
#                 the same with STALE_SECONDS=0     -> 1 "focused, input Ns ago"
#                 after it reports focus-out        -> 1 "<tty> not focused, ..."
#     elsewhere   a focused client on window 1, claude's pane in window 0
#                                    -> 1 "on window 1 (claude's is 0)"
#     zoomed      a focused client on claude's window, zoomed onto the other
#                 pane of a split    -> 1 "zoomed onto another pane"
#     moved       claude's window moved into another session, where a focused
#                 client shows it    -> 0 (a client counts by the window it
#                 shows, not its session), and `session` names the new one
#     panegone    claude's pane killed, another window keeps the session -> 2
#     goes        the session killed                -> 2
#     (no server on the socket)                     -> 2
#     tmuxfail    tmux failing (a wrapper on PATH, "protocol version
#                 mismatch") -> 3 and "tmux -S <socket>: <the message>":
#                 never 2, which the mod reads as nothing left to push about
#   session <$TMUX> <pane>    -> the pane's session, on a socket whose path
#                                has a comma in it too; 2 gone; 3 failing
#
# Exit 0 = all passed.

set -uo pipefail

for cmd in tmux python3; do
  command -v "$cmd" >/dev/null || {
    echo "ntfy_watch_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"
event_log_start ntfy_watch_test --no-prune

WATCH="$REPO/home/.claude/mods/session-done/tmux-watch.sh"
WORK=$(mktemp -d)
# Unix socket paths are capped near 108 bytes, so not under $WORK.
SOCK="/tmp/ntfywatch-$$.sock"
COMMA="/tmp/ntfywatch-$$,b.sock"

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
  tmux -S "$COMMA" kill-server 2>/dev/null
  rm -f "$SOCK" "$COMMA"
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
# pane_of <session id>: the session's first pane, window 0's, where claude
# runs (its $TMUX_PANE)
pane_of() { t list-panes -t "\$$1:0" -F '#{pane_id}' | head -1; }
# tmux_of <session id>: the $TMUX of a claude started in that session
tmux_of() { echo "$SOCK,$$,$1"; }

# wait_focus <session target> <yes|no>: until a client of the session is
# focused, or none is; 6 s at the most.
wait_focus() {
  local has
  for _ in $(seq 30); do
    has=no
    t list-clients -t "$1" -F '#{client_flags}' 2>/dev/null | grep -q focused && has=yes
    [ "$has" = "$2" ] && return
    sleep 0.2
  done
}

# focused_client <session> [<file>]: a real tmux client in a pty, attached to
# the session; the focus-in sequence it is sent is what a terminal emits when
# its window gains focus, which sets client_flags focused and refreshes
# client_activity -- exactly what watched() tests. When <file> appears it
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
# watched: claude's window 0 is the current one of two.
sid_watched=$(new_session watched)
t new-window -d -t "=watched:" 'sleep 1000'
focused_client watched "$WORK/unfocus"
# elsewhere: the client is on window 1, a shell beside claude's.
sid_else=$(new_session elsewhere)
t new-window -t "=elsewhere:" 'sleep 1000'
focused_client elsewhere
# zoomed: claude's window is current, but zoomed onto its other pane.
sid_zoom=$(new_session zoomed)
t split-window -t "=zoomed:0" 'sleep 1000'
t resize-pane -Z -t "=zoomed:0.1"
focused_client zoomed
# moved: claude's window 0 moved into another session and made current
# there, a focused client attached to that one; claude's $TMUX still names
# the session it started in, which keeps a second window.
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

# is <label> <want status> <want output, an extended regex> <tmux-watch.sh args...>
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
# watched_is <label> <want status> <want output> <session id>: `watched` for
# a claude in that session's first pane.
watched_is() { is "$1" "$2" "$3" watched "$(tmux_of "$4")" "$(pane_of "$4")"; }
TTY='(ttys[0-9]+|pts/[0-9]+)'
MISMATCH="^tmux -S $SOCK: protocol version mismatch \(client 8, server 9\)\$"

# --- watched -----------------------------------------------------------------

watched_is "nobody attached" 1 '^no client attached$' "$sid_nobody"
watched_is "a focused client on claude's window" 0 '^$' "$sid_watched"
# The freshness bound: focus alone is not believed. With a bound of 0 no
# input is fresh, as none is after STALE_SECONDS on a locked screen.
CLAUDE_NTFY_STALE_SECONDS=0 watched_is "focused, but its input is stale" 1 "^$TTY focused, input [0-9]+s ago\$" "$sid_watched"
watched_is "a focused client on another window" 1 \
  "^$TTY focused, input [0-9]+s ago, on window 1 \(claude's is 0\)\$" "$sid_else"
watched_is "claude's window zoomed onto another pane" 1 \
  "^$TTY focused, input [0-9]+s ago, claude's window zoomed onto another pane\$" "$sid_zoom"
is "claude's window shown in another session by a focused client" 0 '^$' watched "$(tmux_of "$sid_moved")" "$pane_moved"

# The same client loses focus.
touch "$WORK/unfocus"
wait_focus "\$$sid_watched" no
watched_is "after focus-out" 1 "^$TTY not focused, input [0-9]+s ago\$" "$sid_watched"

# Gone: the pane, the session, the server.
t kill-pane -t "$pane_gone"
is "claude's pane killed, its session kept" 2 '^$' watched "$(tmux_of "$sid_panegone")" "$pane_gone"
t kill-session -t =goes
is "the session killed" 2 '^$' watched "$(tmux_of "$sid_goes")" "$pane_goes"
is "no server on the socket" 2 '^$' watched "$WORK/nosuch.sock,$$,0" %0

# --- session -----------------------------------------------------------------

is "session: where the pane is now" 0 '^movedto$' session "$(tmux_of "$sid_moved")" "$pane_moved"
# A socket path with a comma in it is still the socket: $TMUX is cut from
# the right. A second server, as the path is the server's.
tmux -S "$COMMA" -f /dev/null new-session -d -s comma 'sleep 1000'
is "session, a comma in the socket's path" 0 '^comma$' session "$COMMA,$$,0" \
  "$(tmux -S "$COMMA" list-panes -t '=comma:' -F '#{pane_id}')"
is "session of a pane that is gone" 2 '^$' session "$(tmux_of "$sid_panegone")" "$pane_gone"
is "session with no server on the socket" 2 '^$' session "$WORK/nosuch.sock,$$,0" %0

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
PATH="$WORK/failtmux:$PATH" is "watched, tmux failing" 3 "$MISMATCH" watched "$(tmux_of "$sid_nobody")" "$pane_nobody"
PATH="$WORK/failtmux:$PATH" is "session, tmux failing" 3 "$MISMATCH" session "$(tmux_of "$sid_nobody")" "$pane_nobody"

# --- asked wrongly -----------------------------------------------------------

is "an unknown command" 64 '^tmux-watch.sh: usage: ' bogus
is "watched with no pane" 64 '^tmux-watch.sh: usage: ' watched "$(tmux_of "$sid_nobody")"

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

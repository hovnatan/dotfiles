#!/usr/bin/env bash
# check.sh covers: home/.claude/ntfy-stop.sh scripts/lib/*
#
# ntfy_stop_test.sh -- end-to-end checks for home/.claude/ntfy-stop.sh, the
# Claude Code Stop / UserPromptSubmit hook that pushes to ntfy when a finished
# turn goes unwatched. Runs the hook for real against a throwaway tmux
# server, a throwaway HOME (its own topic file and decision log) and a local
# HTTP listener standing in for ntfy.sh, so nothing reaches a phone. Needs
# tmux and python3; about 20 s, most of it the (shortened) debounce window.
#
#   hook (TMUX=<test socket>,1,<session id>) -- per scenario session:
#     push-ok     unwatched            -> waiter -> POST to the listener
#                 second Stop          -> coalesced into the pending waiter
#     cancelme    unwatched, then a UserPromptSubmit (--cancel)
#     failpush    unwatched, NTFY_URL is a closed port -> "curl exit 7"
#     goes        unwatched, session killed mid-window  -> "session gone"
#     grows       unwatched, transcript keeps growing   -> one "grew" line, push
#     watched     a real client attached in a pty, focus-in sent -> no waiter
#                 then the same client reports focus-out: a waiter is armed,
#                 and the line says what it saw ("<tty> not focused, input
#                 Ns ago"); cancelled before it pushes
#
# Checks the decision log line by line (and that it is an event log under
# ~/.dotfiles/.logs), what the listener received, and that no lock directory
# is left behind. Exit 0 = all passed; on failure the work
# dir (log, listener output) is kept and printed.

set -uo pipefail

for cmd in tmux python3 curl; do
  command -v "$cmd" >/dev/null || {
    echo "ntfy_stop_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$REPO/home/.claude/ntfy-stop.sh"
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 108 bytes, so not under $WORK.
SOCK="/tmp/ntfytest-$$.sock"
# The hook's log: one directory per UTC day under the repo's event logs
# (two, if the test runs across midnight).
ntfy_log() { cat "$H"/.dotfiles/.logs/*_claude_ntfy/events.log 2>/dev/null; }
# The waiter polls every 5 s, so a window holds its polls at 0 and 5 s and
# ends at the one at 10 s. With a 6 s window the poll at 5 s had 1 s to
# spare: a first iteration that took a second longer (five waiters starting
# at once, each pruning logs) put it outside, and grows was pushed with no
# growth seen. 8 s costs no time, the window still ends at the 10 s poll.
DEBOUNCE=8

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
t() { tmux -S "$SOCK" "$@"; }

cleanup() {
  [ -n "${listener:-}" ] && kill "$listener" 2>/dev/null
  [ -n "${client:-}" ] && kill "$client" 2>/dev/null
  [ -n "${toucher:-}" ] && kill "$toucher" 2>/dev/null
  t kill-server 2>/dev/null
  rm -f "$SOCK"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# --- fake ntfy: records every POST, answers 200 ------------------------------

python3 - "$WORK/port" >"$WORK/listener.out" 2>&1 <<'PYEOF' &
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"])).decode()
        print(f"POST {self.path} title={self.headers['Title']!r} body={body!r}", flush=True)
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_port))
srv.serve_forever()
PYEOF
listener=$!
# A cold python3 (first run on a Mac, a fresh CI runner) took over 2 s to
# listen; without a port every push goes to "http://127.0.0.1:" and fails
# as curl exit 7, which reads like a hook bug.
for _ in $(seq 100); do
  [ -s "$WORK/port" ] && break
  sleep 0.1
done
if ! [ -s "$WORK/port" ]; then
  fail "fake ntfy listener wrote no port in 10 s: $(cat "$WORK/listener.out")"
  exit 1
fi
OK_URL="http://127.0.0.1:$(cat "$WORK/port")"
BAD_URL="http://127.0.0.1:9" # discard port: nothing listens -> curl exit 7

# --- throwaway HOME and tmux server ------------------------------------------

mkdir -p "$H/.config/claude-ntfy"
echo testtopic >"$H/.config/claude-ntfy/topic"
touch "$WORK/transcript"

t -f /dev/null new-session -d -s keepalive 'sleep 1000'
t set -g focus-events on
new_session() { # prints the session id without its "$"
  t new-session -d -s "$1" 'sleep 1000'
  t display -p -t "=$1:" '#{session_id}' | tr -d '$'
}

# hook <session id> <url> [--cancel]: one hook invocation, as Claude Code runs it
hook() {
  echo "{\"transcript_path\":\"$WORK/transcript\"}" \
    | env -u TMUX_PANE HOME="$H" TMUX="$SOCK,1,$1" CLAUDE_NTFY_DEBOUNCE_SECONDS=$DEBOUNCE \
      CLAUDE_NTFY_URL="$2" bash "$HOOK" ${3:+"$3"} >>"$WORK/hook.out"
}

# --- a focused client for the "watched" scenario -----------------------------

# A real tmux client in a pty; the focus-in sequence it is sent is what a
# terminal emits when its window gains focus, which sets client_flags focused
# and refreshes client_activity -- exactly what watched() tests.
sid_watched=$(new_session watched)
# When $WORK/unfocus appears it sends the focus-out a terminal emits on losing
# focus, for the second half of the scenario.
python3 - "$SOCK" "$WORK/unfocus" <<'PYEOF' &
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE")} | {"TERM": "xterm-256color"}
    os.execvpe("tmux", ["tmux", "-S", sys.argv[1], "attach", "-t", "=watched"], env)
time.sleep(1); os.write(fd, b"\x1b[I")
end = time.time() + 60; unfocused = False
while time.time() < end:
    if not unfocused and os.path.exists(sys.argv[2]):
        os.write(fd, b"\x1b[O"); unfocused = True
    if select.select([fd], [], [], 0.1)[0]:
        try: os.read(fd, 65536)
        except OSError: break
PYEOF
client=$!
for _ in $(seq 30); do
  t list-clients -t "\$$sid_watched" -F '#{client_flags}' 2>/dev/null | grep -q focused && break
  sleep 0.2
done

# locks_left: true while any waiter lock of this test's socket exists (the
# hook names them <socket basename>-<session id>.lock, see lock_path()).
locks_left() {
  local f
  for f in "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/claude-ntfy/${SOCK##*/}"-*.lock; do
    [ -e "$f" ] && return 0
  done
  return 1
}

# --- the scenarios -----------------------------------------------------------

sid_ok=$(new_session push-ok)
sid_cancel=$(new_session cancelme)
sid_fail=$(new_session failpush)
sid_gone=$(new_session goes)
sid_grows=$(new_session grows)
log "scenarios armed (debounce ${DEBOUNCE}s); work dir $WORK"

hook "$sid_ok" "$OK_URL"
hook "$sid_ok" "$OK_URL"
hook "$sid_cancel" "$OK_URL"
hook "$sid_fail" "$BAD_URL"
hook "$sid_gone" "$OK_URL"
hook "$sid_grows" "$OK_URL"
# grows: keep the transcript growing, every 0.5 s in the background while
# the other scenarios proceed, until the waiter has logged the growth (or
# 30 s). The waiter compares the transcript against its pid file, written
# when it starts, and polls every 5 s, so the touches have to outlast its
# start: a macOS runner has started it over 9 s after the hook armed it, and
# a fixed 9 s of touching then all fell before the pid file ("FAIL grows: 0
# 'transcript grew' lines", push still sent; reproduced by delaying the
# waiter 10 s). With W the waiter's start:
#   W+5   grew -> logged, window re-armed to W+13; the touches stop
#   W+10  the last touch may still count -> same streak, not logged
#   W+15  quiet, and past the window (or W+20, if W+10 re-armed it) -> push
grew() { ntfy_log | grep -F -- "grows (\$$sid_grows)" | grep -qF "wait: transcript grew"; }
(for _ in $(seq 60); do
  sleep 0.5
  touch "$WORK/transcript"
  grew && break
done) &
toucher=$!
hook "$sid_watched" "$OK_URL"
# The same client loses focus: the next Stop arms a waiter, whose line names
# the client as not focused. Cancelled once its lock is there, or the cancel
# finds nothing to cancel and the waiter pushes.
touch "$WORK/unfocus"
for _ in $(seq 30); do
  t list-clients -t "\$$sid_watched" -F '#{client_flags}' 2>/dev/null | grep -q focused || break
  sleep 0.2
done
hook "$sid_watched" "$OK_URL"
for _ in $(seq 50); do
  [ -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/claude-ntfy/${SOCK##*/}-$sid_watched.lock" ] && break
  sleep 0.1
done
hook "$sid_watched" "$OK_URL" --cancel
sleep 2
hook "$sid_cancel" "$OK_URL" --cancel
t kill-session -t =goes
wait "$toucher"

# Wait out the longest window: grows restarts it on each touch.
for _ in $(seq 40); do
  locks_left || break
  sleep 1
done
sleep 1

# --- checks ------------------------------------------------------------------

has() { ntfy_log | grep -F -- "$1" | grep -qF -- "$2"; }
count() { ntfy_log | grep -F -- "$1" | grep -cF -- "$2"; }

has "push-ok (\$$sid_ok)" "push: sent via $OK_URL" && pass "push-ok: pushed" || fail "push-ok: no push logged"
has "push-ok (\$$sid_ok)" "wait: coalesced into pending waiter" && pass "push-ok: second Stop coalesced" || fail "push-ok: second Stop not coalesced"
has "cancelme (\$$sid_cancel)" "prompt: user replied, pending push cancelled" && pass "cancelme: cancelled by the prompt" || fail "cancelme: no cancel logged"
has "cancelme (\$$sid_cancel)" "push:" && fail "cancelme: pushed anyway" || pass "cancelme: never pushed"
has "failpush (\$$sid_fail)" "push: FAILED, curl exit 7" && pass "failpush: failure logged with curl's exit code" || fail "failpush: no 'curl exit 7' line"
has "goes (\$$sid_gone)" "wait: session gone, no push" && pass "goes: session gone, no push" || fail "goes: no 'session gone' line"
[ "$(count "grows (\$$sid_grows)" "wait: transcript grew")" = 1 ] && pass "grows: one 'transcript grew' line for the streak" \
  || fail "grows: $(count "grows (\$$sid_grows)" "wait: transcript grew") 'transcript grew' lines"
has "grows (\$$sid_grows)" "push: sent via $OK_URL" && pass "grows: pushed after the quiet window" || fail "grows: no push"
has "watched (\$$sid_watched)" "stop: watched now, no push" && pass "watched: focused client suppresses the waiter" || fail "watched: not seen as watched"

# The evidence behind "unwatched": what tmux knew of the session's clients.
has "push-ok (\$$sid_ok)" "waiter armed (debounce ${DEBOUNCE}s; no client attached)" \
  && pass "push-ok: armed, and says no client was attached" || fail "push-ok: arm line without its clients: $(ntfy_log | grep -F 'push-ok' | head -1)"
has "push-ok (\$$sid_ok)" "unwatched (no client attached)" \
  && pass "push-ok: the push says the same" || fail "push-ok: push line without its clients: $(ntfy_log | grep -F 'push: sent' | head -1)"
ntfy_log | grep -F "watched (\$$sid_watched) stop: unwatched" | grep -q -E '; (ttys[0-9]+|pts/[0-9]+) not focused, input [0-9]+s ago\)$' \
  && pass "watched: after focus-out it is armed, naming the client as not focused" \
  || fail "watched: no 'not focused' evidence: $(ntfy_log | grep -F "watched (\$$sid_watched)")"
has "watched (\$$sid_watched)" "prompt: user replied, pending push cancelled" && pass "watched: that waiter was cancelled" || fail "watched: waiter not cancelled"

posts=$(grep -c '^POST /testtopic' "$WORK/listener.out")
[ "$posts" = 2 ] && pass "listener got exactly 2 pushes" || fail "listener got $posts pushes"
grep -qF "title='CC: $(hostname)-push-ok'" "$WORK/listener.out" && pass "push title names host and session" || fail "push title wrong: $(head -1 "$WORK/listener.out")"
ntfy_log | grep -q testtopic && fail "the topic leaked into the log" || pass "topic never logged"

# Where and how it logs: with the repo's other event logs, UTC-stamped, and
# nothing on the hook's stdout, which is Claude Code's.
dirs=$(cd "$H/.dotfiles/.logs" 2>/dev/null && ls -d ./*_claude_ntfy 2>/dev/null | wc -l | tr -d ' ')
{ [ "$dirs" = 1 ] || [ "$dirs" = 2 ]; } && pass "one log directory for the day, under ~/.dotfiles/.logs" \
  || fail "$dirs claude_ntfy directories under $H/.dotfiles/.logs: $(ls "$H/.dotfiles/.logs" 2>&1)"
odd=$(ntfy_log | grep -c -v -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z [^ ]+ \(\$[0-9]+\) (stop|wait|prompt|push): ')
[ "$odd" = 0 ] && pass "every line is '<UTC time> <session> (\$<id>) <event>: ...' ($(ntfy_log | wc -l | tr -d ' ') lines)" \
  || fail "$odd line(s) of another form: $(ntfy_log | grep -v -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z ' | head -3)"
[ ! -e "$H/.local/state/claude-ntfy" ] && pass "nothing written to the old ~/.local/state/claude-ntfy" \
  || fail "the old log location was written: $(ls "$H/.local/state/claude-ntfy")"
[ ! -s "$WORK/hook.out" ] && pass "the hook prints nothing on stdout" || fail "hook stdout: $(head -3 "$WORK/hook.out")"
locks_left && fail "lock directories left behind" || pass "no lock directories left"

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

#!/usr/bin/env bash
# check.sh covers: home/.tmux.conf home/.config/tmux/* scripts/appearance.sh scripts/claude_tmux_run.sh scripts/lib/*
#
# tmux_hooks_test.sh -- end-to-end checks for the tmux hooks' log: the hook
# lines of home/.tmux.conf and the scripts they run, in a throwaway tmux
# server and HOME, with a client in a pty that reports focus as a terminal
# does. Needs tmux (3.6 or later, for the focus hooks), python3 and fish
# (report-attach.sh's host report); about 30 s.
#
#   sessions   a: sleep           b: a stand-in "claude" (a link to bash,
#                                    idle on a FIFO; the name and the
#                                    foreground are all
#                                    focus-out-unattached.sh looks at)
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
#   a's pane title "* <host>/renamed"     -> session $N renamed a -> renamed
#   then "* <host>-old" (the form before  -> renamed renamed -> old
#   2026-10-22)
#   client dies                           -> detached ... session=b
#                                            synthetic focus-out to %N (b)
#   an iTerm2-over-ssh attach to a tty    -> exit 1, the reason in the
#   this user cannot write (report-          output tmux shows, FAILED ...
#   attach.sh run as tmux runs a hook)       in the log
#
# Then the window rules, on a second server started from the whole
# home/.tmux.conf, with a client in a pty typing what a terminal would:
#
#   one window                        -> no status bar (another session too)
#   a second window                   -> bar on for that session only; off
#                                        again at one; closing a middle
#                                        window renumbers the rest
#   prefix C n p l w S 0-9, User0/1   -> bound
#   Cmd-K Cmd-K Cmd-J (\e[5;30002~,   -> windows 1, 2, 1, nothing typed into
#   \e[5;30001~ as iTerm2 sends them)    the pane; in a one-window session
#                                        nothing moves and nothing is shown
#   prefix S                          -> bar off, and kept off while windows
#                                        come and go; prefix S -> rule back
#   source-file                       -> the rule applied to every session
#
# The socket is named "claude": sync-session-name.sh acts on that one only.
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux python3 fish; do
  command -v "$cmd" >/dev/null || {
    echo "tmux_hooks_test.sh: $cmd not on PATH" >&2
    exit 1
  }
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
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
cleanup() {
  [ -n "${client:-}" ] && kill "$client" 2>/dev/null
  [ -n "${bystander:-}" ] && kill "$bystander" 2>/dev/null
  [ -n "${wclient:-}" ] && kill "$wclient" 2>/dev/null
  t kill-server 2>/dev/null
  [ -n "${WSOCK:-}" ] && tw kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# The throwaway HOME holds the repo at ~/.dotfiles, where the hook lines
# expect their scripts; the logs land in its .logs, not the checkout's.
#
# The server's PATH is tmux's own directory, then the system's: the hook
# scripts run `tmux`, and it has to be the server's own. A distro tmux found
# first cannot talk to it (Ubuntu's /usr/bin/tmux 3.4 against a 3.7c server:
# "server exited unexpectedly" on every command), which failed every hook
# that calls tmux on the Ubuntu runner while macOS, with no /usr/bin/tmux,
# passed.
mkdir -p "$H/.dotfiles"
ln -s "$REPO/home" "$H/.dotfiles/home"
ln -s "$REPO/scripts" "$H/.dotfiles/scripts"
t() { env -i HOME="$H" PATH="$(dirname "$TMUX_BIN"):/usr/bin:/bin" TERM=xterm-256color "$TMUX_BIN" -S "$SOCK" "$@"; }
hooks_log() { cat "$H"/.dotfiles/.logs/*_tmux_hooks/events.log 2>/dev/null; }
# wait_for <pattern>: until the log has a line matching it, 5 s at most
wait_for() {
  for _ in $(seq 50); do
    hooks_log | grep -q -E -- "$1" && return 0
    sleep 0.1
  done
  return 1
}

# bash, not sleep: Ubuntu 26.04's sleep is uutils' multi-call binary, which
# refuses to run under another name (a copy: "coreutils: unknown program
# 'claude'"). The FIFO has no writer, so read just waits.
ln -s "$(command -v bash)" "$WORK/claude"
mkfifo "$WORK/never"
grep -E '^set-hook -g (client-(attached|detached|session-changed|focus-in|focus-out)|pane-title-changed)' \
  "$REPO/home/.tmux.conf" >"$WORK/hooks.conf"
t -f /dev/null new-session -d -s a 'sleep 300'
t new-session -d -s b "$WORK/claude -c 'read -r -t 300 <>$WORK/never'"
t set -g focus-events on
if t source-file "$WORK/hooks.conf" 2>"$WORK/out"; then
  pass "$("$TMUX_BIN" -V) takes the $(wc -l <"$WORK/hooks.conf" | tr -d ' ') hook lines of home/.tmux.conf"
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
for _ in $(seq 50); do
  [ -n "$(t list-clients -t =b -F '#{client_tty}')" ] && break
  sleep 0.1
done
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

t select-pane -t a -T "* $HOSTNAME/renamed"
wait_for " session \\\$[0-9]+ renamed a -> renamed \\(pane title \"\\* $HOSTNAME/renamed\"\\)\$" \
  && pass "a rename from the pane title is logged" || fail "no rename line: $(hooks_log)"
[ "$(t list-sessions -F '#{session_name}' | sort | tr '\n' ' ')" = "b renamed " ] \
  && pass "and the session is renamed" || fail "sessions: $(t list-sessions -F '#{session_name}' | tr '\n' ' ')"
# A conversation not yet reloaded still carries "<host>-<name>".
t select-pane -t renamed -T "* $HOSTNAME-old"
wait_for " session \\\$[0-9]+ renamed renamed -> old \\(pane title \"\\* $HOSTNAME-old\"\\)\$" \
  && pass "the old <host>-<name> title still renames the session" || fail "no rename from $HOSTNAME-old: $(hooks_log)"

# wait: without it bash prints the killed job, heredoc and all.
kill "$client"
wait "$client" 2>/dev/null
client=
wait_for " detached $client_tty session=b\$" && pass "the detach is logged, naming the client" || fail "no detached line: $(hooks_log)"
# b keeps its bystander until now: only with it gone is the claude pane
# without a client.
kill "$bystander"
wait "$bystander" 2>/dev/null
bystander=
wait_for ' synthetic focus-out to %[0-9]+ \(b\): no client attached$' \
  && pass "the focus-out sent to the clientless claude pane is logged" || fail "no synthetic focus-out line: $(hooks_log)"

# --- an attach report that cannot be written -----------------------------------------

# An iTerm2 client over ssh on a tty this user cannot write, as a Tailscale
# SSH pty that ran a remote command stays root's: a read-only file stands in
# for it. run-shell is how tmux runs the hook, and shows only its stdout
# with the "returned 1": that is where the reason has to be. The host
# report comes from fish (iterm2_report_host), so the throwaway HOME gets
# the repo's fish functions and the server's PATH fish's directory.
mkdir -p "$H/.config/fish"
ln -s "$REPO/home/.config/fish/functions" "$H/.config/fish/functions"
t set-environment -g PATH "$(dirname "$TMUX_BIN"):/usr/bin:/bin:$(dirname "$(command -v fish)")"
ro_tty="$WORK/ro_tty"
: >"$ro_tty"
chmod 444 "$ro_tty"
[ "$(id -u)" != 0 ] || fail "running as root, which writes a read-only file: the next checks cannot fail"
t set-environment -t b LC_TERMINAL iTerm2
t set-environment -t b SSH_CONNECTION "192.0.2.1 50000 192.0.2.2 22"
# The session id ("$1") quoted, as the hook line's #{q:session_id} does.
out=$(t run-shell "$H/.dotfiles/home/.config/tmux/report-attach.sh $SOCK '$(t display -p -t b '#{session_id}')' ro $ro_tty attached" 2>&1)
case $out in
  *"cannot write the iTerm2 host report to $ro_tty. Likely a Tailscale SSH login"*"returned 1"*)
    pass "an unwritable tty fails the hook, the reason shown with it"
    ;;
  *) fail "unwritable tty output: $out" ;;
esac
# Run directly, where stderr is not dropped: bash's own "Permission denied"
# for the redirection would be noise beside the reason.
err=$(env -i HOME="$H" PATH="$(dirname "$TMUX_BIN"):/usr/bin:/bin:$(dirname "$(command -v fish)")" \
  "$H/.dotfiles/home/.config/tmux/report-attach.sh" "$SOCK" "$(t display -p -t b '#{session_id}')" ro "$ro_tty" attached 2>&1 >/dev/null)
[ -z "$err" ] && pass "and nothing on stderr" || fail "stderr of the failing hook: $err"
wait_for " attached $ro_tty session=b: iTerm2 over ssh, FAILED: cannot write to $ro_tty\$" \
  && pass "the failure is logged, naming the tty" || fail "no FAILED line: $(hooks_log)"

# --- windows: the status bar, the bindings, Cmd-J / Cmd-K ------------------------------

# A server of its own, started from the whole home/.tmux.conf (the window
# rules are spread over it), with a client in a pty that types what it is
# told: each line written to $WORK/keys is sent as the bytes it spells
# (Python escapes, "\x01S" = prefix S). Panes run sleep: the config's
# default-command is fish, and nothing here needs a shell.
WSOCK="$SOCKDIR/win"
tw() { env -i HOME="$H" PATH="$(dirname "$TMUX_BIN"):/usr/bin:/bin" TERM=xterm-256color "$TMUX_BIN" -S "$WSOCK" "$@"; }
status_of() { tw show -v -t "$1": status 2>&1; }
current() { tw display -p -t "$1": '#{window_index}'; }
mkfifo "$WORK/keys"
tw -f "$H/.dotfiles/home/.tmux.conf" new-session -d -s w -x 120 -y 30 'sleep 300' 2>"$WORK/out" \
  || fail "the server would not start from home/.tmux.conf: $(cat "$WORK/out")"
tw new-session -d -s solo 'sleep 300'
[ "$(status_of w)" = off ] && [ "$(status_of solo)" = off ] \
  && pass "a session of one window has no status bar" || fail "one window: status w=$(status_of w) solo=$(status_of solo)"

python3 - "$TMUX_BIN" "$WSOCK" "$H" "$WORK/keys" "$WORK/screen" <<'PYEOF' &
import os, pty, select, sys
tmux, sock, home, keys, screen = sys.argv[1:]
out = open(screen, "wb", buffering=0)  # what the terminal was sent to draw
pid, fd = pty.fork()
if pid == 0:
    os.execve(tmux, [tmux, "-S", sock, "attach", "-t", "=w"], {"HOME": home, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color"})
kfd = os.open(keys, os.O_RDWR)  # RDWR: no EOF while no writer is open
buf = b""
while True:
    r = select.select([fd, kfd], [], [], 0.1)[0]
    if kfd in r:
        buf += os.read(kfd, 4096)
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            os.write(fd, line.decode().encode("latin-1").decode("unicode_escape").encode("latin-1"))
    if fd in r:
        try:
            data = os.read(fd, 65536)
        except OSError: break
        if not data: break
        out.write(data)
PYEOF
wclient=$!
# send_keys <python escapes>: what the terminal would send; tmux handles it at once,
# the pause lets the commands it runs (run-shell -C) finish
send_keys() {
  printf '%s\n' "$1" >"$WORK/keys"
  sleep 0.5
}
for _ in $(seq 50); do
  [ -n "$(tw list-clients -t =w -F '#{client_tty}')" ] && break
  sleep 0.1
done

tw new-window -d -t =w: 'sleep 300'
sleep 0.3
[ "$(status_of w)" = on ] && [ "$(status_of solo)" = off ] \
  && pass "a second window turns the bar on for that session only" || fail "two windows: w=$(status_of w) solo=$(status_of solo)"
tw new-window -d -t =w: 'sleep 300'
tw kill-window -t =w:1
sleep 0.3
[ "$(tw list-windows -t =w: -F '#I' | tr '\n' ' ')" = "0 1 " ] && [ "$(status_of w)" = on ] \
  && pass "closing a middle window renumbers the rest (0 1), the bar stays" \
  || fail "after closing window 1: windows $(tw list-windows -t =w: -F '#I' | tr '\n' ' '), status $(status_of w)"
tw kill-window -t =w:1
sleep 0.3
[ "$(status_of w)" = off ] && pass "back to one window, the bar goes" || fail "back to one: status $(status_of w)"

missing=""
for k in C n p l w S 0 1 2 3 4 5 6 7 8 9; do
  tw list-keys -T prefix "$k" >/dev/null 2>&1 || missing+=" prefix-$k"
done
for k in User0 User1; do
  tw list-keys -T root "$k" >/dev/null 2>&1 || missing+=" $k"
done
[ -z "$missing" ] && pass "window bindings: prefix C n p l w S 0-9, User0 User1" || fail "unbound:$missing"

# Cmd-J / Cmd-K, as iTerm2 and Ghostty send them. In a one-window session
# nothing moves, and tmux draws no "No next window" (an unguarded
# next-window does, on the client's screen, not in show-messages).
send_keys '\x1b[5;30002~'
send_keys '\x1b[5;30001~'
[ "$(current w)" = 0 ] && ! grep -aq 'No \(next\|previous\) window' "$WORK/screen" \
  && pass "Cmd-J/K in a one-window session: nothing moves, no message" \
  || fail "one window: current $(current w), screen: $(grep -ao 'No [a-z]* window' "$WORK/screen" | head -2)"
tw new-window -d -t =w: 'sleep 300'
tw new-window -d -t =w: 'sleep 300'
sleep 0.3
send_keys '\x1b[5;30002~'
a=$(current w)
send_keys '\x1b[5;30002~'
b=$(current w)
send_keys '\x1b[5;30001~'
c=$(current w)
[ "$a $b $c" = "1 2 1" ] && pass "Cmd-K, Cmd-K, Cmd-J: window 1, 2, 1" || fail "Cmd-K, Cmd-K, Cmd-J landed on $a $b $c"
pane_text=$(tw capture-pane -p -t =w:1)
[ -z "$(tr -d ' \n' <<<"$pane_text")" ] && pass "and nothing leaks into the pane" || fail "pane shows: $pane_text"

# prefix S hides the bar, and it stays hidden while windows come and go;
# prefix S again brings back the automatic rule.
send_keys '\x01S'
[ "$(status_of w)" = off ] && pass "prefix S hides the bar at once (3 windows)" || fail "after prefix S: status $(status_of w)"
tw new-window -d -t =w: 'sleep 300'
tw kill-window -t =w:3
tw kill-window -t =w:2
sleep 0.3
[ "$(status_of w)" = off ] && pass "hidden, adding and closing windows leaves it off" || fail "hidden, after window changes: status $(status_of w)"
send_keys '\x01S'
[ "$(status_of w)" = on ] && pass "prefix S again: the bar is back (2 windows)" || fail "after prefix S again: status $(status_of w)"

# A reload applies the rule to sessions that changed while it was not loaded.
tw set-option -t =solo: status off
tw new-window -d -t =solo: 'sleep 300'
tw set-option -t =solo: status off
tw source-file "$H/.dotfiles/home/.tmux.conf"
sleep 0.3
[ "$(status_of solo)" = on ] && pass "a reload sets the bar for every session" || fail "after reload: solo status $(status_of solo)"
kill "$wclient"
wait "$wclient" 2>/dev/null
wclient=
tw kill-server 2>/dev/null

# --- the log as a whole ---------------------------------------------------------------

odd=$(hooks_log | grep -c -v -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ')
[ "$odd" = 0 ] && pass "every line is UTC-stamped ($(hooks_log | wc -l | tr -d ' ') lines, one file for all the hooks)" \
  || fail "$odd line(s) without a UTC stamp"

log "$failures failure(s)"
[ "$failures" -eq 0 ]

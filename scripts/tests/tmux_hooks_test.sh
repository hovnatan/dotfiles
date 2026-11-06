#!/usr/bin/env bash
# check.sh covers: home/.config/tmux/* scripts/appearance.sh scripts/lib/*
#
# tmux_hooks_test.sh -- end-to-end checks for the tmux hooks' log: the hook
# lines of home/.config/tmux/tmux.conf and the scripts they run, in a throwaway tmux
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
#   client dies                           -> detached ... session=b
#                                            synthetic focus-out to %N (b)
#   an iTerm2-over-ssh attach to a tty    -> exit 1, the reason in the
#   this user cannot write (report-          output tmux shows, FAILED ...
#   attach.sh run as tmux runs a hook)       in the log
#
# Then the window rules, on a second server started from the whole
# home/.config/tmux/tmux.conf, with a client in a pty typing what a terminal would:
#
#   one window, two windows           -> the bar on, on top, "[<session>] |
#                                        cpu N% mem N% | <date time zone>"
#                                        on the right (a stub
#                                        tmux-mem-cpu-load in the throwaway
#                                        HOME); closing a middle window
#                                        renumbers the rest
#   @ssh set on the session           -> "(<host>) [<session>] | cpu ..."
#   a session of a 40-column name     -> the title cut to 32 columns and
#                                        "...", the clock still drawn
#   status-stats.sh                   -> no tool, or output of another
#                                        form: the reason, exit 1
#   panes setting titles; one that    -> each window named after its
#   sets none                            pane's title, glyph and all, and
#                                        renamed when it changes; the
#                                        titleless one after its program
#   prefix c C n p l C-s w s S 0-9,   -> bound; c new window, C new
#   User0/1                              session, C-s and l last window,
#                                        s the session picker
#   Cmd-K Cmd-K Cmd-J (\e[5;30002~,   -> windows 1, 2, 1, nothing typed into
#   \e[5;30001~ as iTerm2 sends them)    the pane; in a one-window session
#                                        nothing moves and nothing is shown
#   Ctrl-u, then Ctrl-d, in a plain   -> copy mode half a page up; back at
#   pane                                 the bottom, copy mode gone
#   wheel up, up, down, down          -> copy mode 5 lines up, then 10; back
#                                        at the bottom, copy mode gone
#   click on a window in the bar      -> that window selected
#   Ctrl-click on one                 -> it and the current window swapped
#   a bell in a window out of view    -> its label on a red background
#   prefix c from window 0 of 3       -> new window at 1, the rest move up
#   prefix S                          -> bar off for that session only, kept
#                                        off while windows come and go;
#                                        prefix S -> back on
#   source-file over the old rule     -> its hooks and per-session values
#   (bar only with 2+ windows)           cleared: the bar on everywhere
#
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
SOCK="$SOCKDIR/hooks"
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
  "$REPO/home/.config/tmux/tmux.conf" >"$WORK/hooks.conf"
t -f /dev/null new-session -d -s a 'sleep 300'
t new-session -d -s b "$WORK/claude -c 'read -r -t 300 <>$WORK/never'"
t set -g focus-events on
if t source-file "$WORK/hooks.conf" 2>"$WORK/out"; then
  pass "$("$TMUX_BIN" -V) takes the $(wc -l <"$WORK/hooks.conf" | tr -d ' ') hook lines of home/.config/tmux/tmux.conf"
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

# --- session switch, detach ---------------------------------------------------------

t switch-client -c "$client_tty" -t b
wait_for ' session-changed [^ ]+ session=b: not iTerm2, local: @ssh unset$' \
  && pass "a session switch is logged" || fail "no session-changed line: $(hooks_log)"

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

# A server of its own, started from the whole home/.config/tmux/tmux.conf (the window
# rules are spread over it), with a client in a pty that types what it is
# told: each line written to $WORK/keys is sent as the bytes it spells
# (Python escapes, "\x01S" = prefix S). Panes run sleep: the config's
# default-command is fish, and nothing here needs a shell.
WSOCK="$SOCKDIR/win"
tw() { env -i HOME="$H" PATH="$(dirname "$TMUX_BIN"):/usr/bin:/bin" TERM=xterm-256color "$TMUX_BIN" -S "$WSOCK" "$@"; }
# status_of <session>: the bar as the session sees it, its own value or the
# global one it inherits
status_of() { tw display -p -t "$1": '#{status}' 2>&1; }
current() { tw display -p -t "$1": '#{window_index}'; }
mkfifo "$WORK/keys"
# The bar's CPU and memory: status-stats.sh runs $HOME/.nix-profile/bin/
# tmux-mem-cpu-load, here a stub printing what 3.8.3 prints (memory first,
# then CPU, a NUL byte before the newline) or, with $WORK/stats_odd there,
# something else.
mkdir -p "$H/.nix-profile/bin"
cat >"$H/.nix-profile/bin/tmux-mem-cpu-load" <<EOF
#!/bin/sh
[ -e "$WORK/stats_odd" ] && { echo "1.2 GB"; exit 0; }
printf '73.98%%   7.8%%\000\n'
EOF
chmod +x "$H/.nix-profile/bin/tmux-mem-cpu-load"
# tw_stop: end the server and wait until it has gone: a client started while
# it dies gets "server exited unexpectedly".
tw_stop() {
  local pid
  pid=$(tw display-message -p '#{pid}' 2>/dev/null) || return 0
  tw kill-server
  for _ in $(seq 50); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  fail "tmux server $pid outlived kill-server by 5 s"
}
stats() { env -i HOME="$H" PATH=/usr/bin:/bin "$H/.dotfiles/home/.config/tmux/status-stats.sh" 2>&1; }
out=$(stats)
rc=$?
[ "$rc" = 0 ] && [ "$out" = "cpu 7.8% mem 74.0%" ] && pass "status-stats.sh labels the tool's numbers: '$out'" \
  || fail "status-stats.sh: rc=$rc '$out'"
touch "$WORK/stats_odd"
out=$(stats)
rc=$?
rm -f "$WORK/stats_odd"
[ "$rc" = 1 ] && grep -qF "printed '1.2 GB', not" <<<"$out" && pass "status-stats.sh refuses output of another form: '$out'" \
  || fail "status-stats.sh on odd output: rc=$rc '$out'"
out=$(env -i HOME="$WORK/nohome" PATH=/usr/bin:/bin "$H/.dotfiles/home/.config/tmux/status-stats.sh" 2>&1)
rc=$?
[ "$rc" = 1 ] && grep -qF "no $WORK/nohome/.nix-profile/bin/tmux-mem-cpu-load" <<<"$out" \
  && pass "status-stats.sh without the tool says so: '$out'" || fail "status-stats.sh without the tool: rc=$rc '$out'"
tw -f "$H/.dotfiles/home/.config/tmux/tmux.conf" new-session -d -s w -x 120 -y 30 'sleep 300' 2>"$WORK/out" \
  || fail "the server would not start from home/.config/tmux/tmux.conf: $(cat "$WORK/out")"
tw new-session -d -s solo 'sleep 300'
[ "$(status_of w)" = on ] && [ "$(status_of solo)" = on ] && [ "$(tw show -gv status-position)" = top ] \
  && pass "a session of one window has the bar, on top" \
  || fail "one window: status w=$(status_of w) solo=$(status_of solo), position $(tw show -gv status-position), right '$(tw show -gv status-right)'"

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
# What the client draws on the right: the stub's numbers labelled, a bar,
# the server's date, time and zone. The first draw has the date alone (the
# job still running), so wait for the second. The minute by pattern: it
# may turn between this line and the draw.
stats_clock="cpu 7\.8% mem 74\.0% \| $(tw display -p '%d %b') [0-9]{2}:[0-9]{2} $(tw display -p '%Z')"
want="\[w\] \| $stats_clock"
for _ in $(seq 50); do
  grep -aqE "$want" "$WORK/screen" && break
  sleep 0.1
done
grep -aqE "$want" "$WORK/screen" && pass "the bar draws '$(grep -aoE "$want" "$WORK/screen" | tail -1)' on the right" \
  || fail "the bar never drew '$want'; screen: $(tr -c '[:print:]' ' ' <"$WORK/screen" | grep -o '[a-z]* [0-9.]*% [^E]*' | tail -2)"

# Over ssh the bar names the machine, as the terminal title does. After the
# attach's own report, which would otherwise unset @ssh behind this check.
wait_for ' attached [^ ]+ session=w: not iTerm2, local: @ssh unset$' \
  || fail "no attach report for w: $(hooks_log | tail -3)"
tw set -t =w: @ssh 1
tw refresh-client -t "$(tw list-clients -t =w -F '#{client_name}')"
want="\($(tw display -p '#{host_short}')\) \[w\] \| $stats_clock"
for _ in $(seq 50); do
  grep -aqE "$want" "$WORK/screen" && break
  sleep 0.1
done
grep -aqE "$want" "$WORK/screen" && pass "over ssh the bar names the machine: '$(grep -aoE "$want" "$WORK/screen" | tail -1)'" \
  || fail "the bar never drew '$want'; screen: $(tr -c '[:print:]' ' ' <"$WORK/screen" | grep -o '[a-z]* [0-9.]*% [^E]*' | tail -2)"
tw set -t =w: -u @ssh

# A long session name gives way, not the clock: tmux trims status-right from
# its end, so a name left whole would cut the date off instead.
long=$(printf 'n%.0s' {1..40})
tw new-session -d -s "$long" 'sleep 300'
tw switch-client -t "=$long"
want="\[$(printf 'n%.0s' {1..31})\.\.\. \| $stats_clock"
for _ in $(seq 1 50); do
  grep -aqE "$want" "$WORK/screen" && break
  sleep 0.1
done
grep -aqE "$want" "$WORK/screen" && pass "a long session name is cut, the clock kept: '$(grep -aoE "$want" "$WORK/screen" | tail -1)'" \
  || fail "the bar never drew '$want'; screen: $(tr -c '[:print:]' ' ' <"$WORK/screen" | grep -o '[a-z]* [0-9.]*% [^E]*' | tail -2)"
tw switch-client -t =w
tw kill-session -t "=$long"

tw new-window -d -t =w: 'sleep 300'
sleep 0.3
[ "$(status_of w)" = on ] && [ "$(status_of solo)" = on ] \
  && pass "a second window keeps the bar" || fail "two windows: w=$(status_of w) solo=$(status_of solo)"
tw new-window -d -t =w: 'sleep 300'
tw kill-window -t =w:1
sleep 0.3
[ "$(tw list-windows -t =w: -F '#I' | tr '\n' ' ')" = "0 1 " ] && [ "$(status_of w)" = on ] \
  && pass "closing a middle window renumbers the rest (0 1), the bar stays" \
  || fail "after closing window 1: windows $(tw list-windows -t =w: -F '#I' | tr '\n' ' '), status $(status_of w)"
tw kill-window -t =w:1
sleep 0.3
[ "$(status_of w)" = on ] && pass "back to one window, the bar stays" || fail "back to one: status $(status_of w)"

# Window names: each window takes its pane's title as the program reports
# it. Stand-ins: a pane setting a title as Claude Code does (glyph first),
# one setting nvim's and then fish's (the change must rename the window),
# and one that sets none (tmux's initial title, the host name, so the
# window is named after the program). tmux re-checks a name only after the
# pane prints, so the titleless one is a copy of bash named "notitle" that
# keeps printing with builtins: no child, the pane's command stays notitle.
# A copy of the real file: macOS kills a copied wrapper or system binary.
mkdir -p "$WORK/cc"
real_bash=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$(command -v bash)")
cp "$real_bash" "$WORK/cc/notitle"
# title_then <title> <command...>: set the pane title, then run the command.
# The glyph as UTF-8 bytes: this file stays ASCII.
cat >"$WORK/cc/title_then" <<'EOF'
#!/bin/sh
printf '\033]2;%s\033\\' "$1"
shift
exec "$@"
EOF
chmod +x "$WORK/cc/title_then"
cc_title=$'\342\234\263'" vm/backend/fix-ci"
tw new-session -d -s cc "$WORK/cc/title_then '$cc_title' sleep 300"
tw new-window -d -t =cc: "$WORK/cc/title_then 'nvim: init.lua' sh -c 'sleep 1; exec $WORK/cc/title_then fish:~/x sleep 300'"
tw new-window -d -t =cc: "$WORK/cc/notitle -c 'while :; do echo .; read -r -t 0.3; done'"
# -u: the client tw starts has no locale (env -i), and without it tmux
# prints the glyph as "_"
names() { tw -u list-windows -t =cc: -F '#{window_name}' | paste -sd '|' -; }
wait_names() {
  for _ in $(seq 40); do
    [ "$(names)" = "$1" ] && return 0
    sleep 0.1
  done
  return 1
}
wait_names "$cc_title|nvim: init.lua|notitle" \
  && pass "windows are named after their pane's title as reported (glyph kept), a titleless one after its program" \
  || fail "window names: '$(names)', titles $(tw list-panes -s -t =cc: -F '#{pane_title}' | paste -sd '|' -)"
wait_names "$cc_title|fish:~/x|notitle" && pass "a new title renames the window" \
  || fail "after window 1's title changed: '$(names)'"
tw kill-session -t =cc

# what_key <table> <key>: the command that key runs, nothing when unbound.
# From the whole table: `list-keys -T <table> <key>` prints nothing and
# exits 0 for a bound and an unbound key alike (tmux 3.7c), so it cannot
# tell them apart.
what_key() {
  tw list-keys -T "$1" | awk -v k="$2" '{
    i = ($2 == "-r") ? 3 : 2 # "bind-key [-r] -T <table> <key> <command>"
    if ($1 == "bind-key" && $i == "-T" && $(i + 2) == k) {
      sub(/^bind-key +(-r +)?-T +[^ ]+ +[^ ]+ +/, ""); print; exit
    }
  }'
}
missing=""
for k in c C n p l C-s w s S 0 1 2 3 4 5 6 7 8 9; do
  [ -n "$(what_key prefix "$k")" ] || missing+=" prefix-$k"
done
for k in User0 User1; do
  [ -n "$(what_key root "$k")" ] || missing+=" $k"
done
[ -z "$missing" ] && pass "window bindings: prefix c C n p l C-s w s S 0-9, User0 User1" || fail "unbound:$missing"
[ -z "$(what_key prefix z)" ] || fail "what_key reads prefix z, which the config leaves unbound, as bound: '$(what_key prefix z)'"
[[ "$(what_key prefix c)" == "new-window -a -c "* ]] && [[ "$(what_key prefix C)" == *"new-session -s "* ]] \
  && [ "$(what_key prefix C-s)" = last-window ] && [ "$(what_key prefix l)" = last-window ] \
  && [ "$(what_key prefix s)" = "choose-tree -Zs" ] \
  && pass "prefix c: new window, C: new session, C-s and l: last window, s: session picker" \
  || fail "prefix c '$(what_key prefix c)', C '$(what_key prefix C)', C-s '$(what_key prefix C-s)', l '$(what_key prefix l)', s '$(what_key prefix s)'"

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

# prefix S hides the bar for its session only, and it stays hidden while
# windows come and go; prefix S again brings it back.
send_keys '\x01S'
[ "$(status_of w)" = off ] && [ "$(status_of solo)" = on ] \
  && pass "prefix S hides the bar at once, in that session only" || fail "after prefix S: status w=$(status_of w) solo=$(status_of solo)"
tw new-window -d -t =w: 'sleep 300'
tw kill-window -t =w:3
tw kill-window -t =w:2
sleep 0.3
[ "$(status_of w)" = off ] && pass "hidden, adding and closing windows leaves it off" || fail "hidden, after window changes: status $(status_of w)"
send_keys '\x01S'
[ "$(status_of w)" = on ] && pass "prefix S again: the bar is back (2 windows)" || fail "after prefix S again: status $(status_of w)"

# Ctrl-d through a real client, as send-keys skips the key tables. Each pane records
# the bytes it is sent, under a name tmux reports as its command: `claude` on Linux,
# the version on macOS, where Delete (ESC [ 3 ~) replaces Ctrl-d. Anything else keeps it.
# They are copies: macOS reports a link to bash as `bash`.
mkdir "$WORK/named"
for name in claude 2.1.318 other-program; do cp "$(command -v bash)" "$WORK/named/$name"; done
ctrl_d_reaches() {
  tw new-window -t =w: "'$WORK/named/$1' -c 'stty raw -echo; cat >\"$WORK/ctrl_d_got\"; :'"
  sleep 0.5
  send_keys '\x04'
  od -An -tx1 "$WORK/ctrl_d_got" | tr -d ' '
  tw kill-window
}
for name in claude 2.1.318; do
  got=$(ctrl_d_reaches "$name")
  [ "$got" = 1b5b337e ] && pass "Ctrl-d in $name arrives as Delete" || fail "Ctrl-d in $name sent: $got"
done
got=$(ctrl_d_reaches other-program)
[ "$got" = 04 ] && pass "Ctrl-d in any other program stays Ctrl-d" || fail "Ctrl-d in other-program sent: $got"

# Ctrl-u in a plain pane: copy mode, half a page up, the step Ctrl-u and Ctrl-d take
# inside copy mode. Ctrl-d then lands back on the bottom line, which leaves copy mode.
tw new-window -t =w: "seq 500; exec sleep 100"
sleep 0.5
half=$(($(tw display -p -t =w: '#{pane_height}') / 2))
send_keys '\x15'
got=$(tw display -p -t =w: '#{pane_in_mode} #{scroll_position}')
[ "$got" = "1 $half" ] && pass "Ctrl-u: copy mode, half a page up" || fail "Ctrl-u: mode and position $got, wanted 1 $half"
send_keys '\x04'
got=$(tw display -p -t =w: '#{pane_in_mode}')
[ "$got" = 0 ] && pass "Ctrl-d back to the bottom leaves copy mode" || fail "after Ctrl-d: pane_in_mode $got"

# The wheel, as SGR mouse reports (button 64 up, 65 down, at column 10, row 10): the
# notch that opens copy mode moves 5 lines, the same as a notch inside it.
send_keys '\x1b[<64;10;10M'
got=$(tw display -p -t =w: '#{pane_in_mode} #{scroll_position}')
[ "$got" = "1 5" ] && pass "first wheel notch up: copy mode, 5 lines up" || fail "first wheel notch: mode and position $got, wanted 1 5"
send_keys '\x1b[<64;10;10M'
got=$(tw display -p -t =w: '#{pane_in_mode} #{scroll_position}')
[ "$got" = "1 10" ] && pass "next wheel notch up: 5 lines more" || fail "next wheel notch: mode and position $got, wanted 1 10"
send_keys '\x1b[<65;10;10M'
send_keys '\x1b[<65;10;10M'
got=$(tw display -p -t =w: '#{pane_in_mode}')
[ "$got" = 0 ] && pass "wheel back to the bottom leaves copy mode" || fail "after wheel down: pane_in_mode $got"
tw kill-window

# A click on a window's name in the bar (top row, status-left empty, so column 2 is the
# first window's label), as an SGR press and release. The new window is the current one.
tw new-window -t =w: "exec sleep 100"
sleep 0.5
first=$(tw list-windows -t =w -F '#{window_index}' | head -1)
last=$(tw display -p -t =w: '#{window_index}')
send_keys '\x1b[<0;2;1M'
send_keys '\x1b[<0;2;1m'
got=$(tw display -p -t =w: '#{window_index}')
[ "$first" != "$last" ] && [ "$got" = "$first" ] \
  && pass "a click on a window in the bar selects it" \
  || fail "click on the bar: window $got, wanted $first (was on $last)"

# Ctrl-click (SGR button 16) on that label, from the last window: the two trade numbers.
first_id=$(tw display -p -t "=w:$first" '#{window_id}')
last_id=$(tw display -p -t "=w:$last" '#{window_id}')
tw select-window -t "=w:$last"
send_keys '\x1b[<16;2;1M'
send_keys '\x1b[<16;2;1m'
got="$(tw display -p -t "=w:$first" '#{window_id}') $(tw display -p -t "=w:$last" '#{window_id}')"
[ "$got" = "$last_id $first_id" ] && pass "a Ctrl-click on a window in the bar swaps it with the current one" \
  || fail "Ctrl-click on the bar: windows $first and $last hold $got, wanted $last_id $first_id"
tw kill-window -t "$last_id"

# A bell in a window out of view: its label is drawn on a red background (#cc241d, as
# the RGB parameters the client is sent).
tw new-window -d -t =w: "printf '\\a'; exec sleep 100"
sleep 0.5
grep -aq '48;2;204;36;29' "$WORK/screen" && pass "a bell paints its window's label red in the bar" \
  || fail "no red background drawn; flags: $(tw list-windows -t =w -F '#{window_index}:#{window_bell_flag}' | tr '\n' ' ')"

# prefix c from window 0 of three: the new window takes number 1, the old 1 moves to
# 2. The panes need no shell, so the new one runs sleep in place of the config's fish.
tw set-option -g default-command 'sleep 300'
tw select-window -t =w:0
was_1=$(tw display -p -t =w:1 '#{window_id}')
send_keys '\x01c'
got="$(current w) $(tw display -p -t =w:2 '#{window_id}')"
[ "$got" = "1 $was_1" ] && pass "prefix c opens the new window next to the current one" \
  || fail "prefix c: current window and window 2 are $got, wanted 1 $was_1"

kill "$wclient"
wait "$wclient" 2>/dev/null
wclient=
tw_stop

# --- a Mac: what a closed pane left -------------------------------------------------

# reap-panes-macos.sh by way of the real hooks. The job is this bash, not an
# Apple binary, whose environment ps would hide; its parent exits, so it is
# detached. Each carries a number of its own, to be found by.
if [ "$(uname)" = Darwin ]; then
  BASH_BIN=$(command -v bash)
  GONE=$((300000 + $$ % 100000)) STAY=$((GONE + 100000)) RETRY=$((GONE + 200000)) # numbers no other run holds
  # detached_job <timeout>: a pane that leaves a job behind and idles; prints
  # the pane's id.
  detached_job() {
    tw new-window -d -P -F '#{pane_id}' -t =w: \
      "sh -c '(nohup $BASH_BIN -c \"read -r -t $1 <>$WORK/never\" </dev/null >/dev/null 2>&1 &) ; exec sleep 300'"
  }
  job_of() { # <timeout>: the job's pid, once it is up. Anchored: the pane's
    # own sh -c line holds the same words until it execs.
    for _ in $(seq 30); do
      pgrep -f -- "^$BASH_BIN -c read -r -t $1 " && return
      sleep 0.1
    done
  }
  ended() { # <pid>: true once it has exited, within 6 s
    for _ in $(seq 60); do
      kill -0 "$1" 2>/dev/null || return 0
      sleep 0.1
    done
    return 1
  }

  tw -f "$H/.dotfiles/home/.config/tmux/tmux.conf" new-session -d -s w -x 120 -y 30 'sleep 300'
  gone_pane=$(detached_job "$GONE")
  stay_pane=$(detached_job "$STAY")
  gone_job=$(job_of "$GONE")
  stay_job=$(job_of "$STAY")
  tw kill-pane -t "$gone_pane"
  [ -n "$gone_job" ] && ended "$gone_job" && pass "a closed pane's detached job ended with it" \
    || fail "job ${gone_job:-none} outlived its pane: $(ps -o command= -p "${gone_job:-0}")"
  kill -0 "$stay_job" 2>/dev/null && [ "$(tw display -p -t "$stay_pane" '#{pane_id}')" = "$stay_pane" ] \
    && pass "a live pane's job stayed" || fail "job ${stay_job:-none} of the live pane $stay_pane is gone"
  hooks_log | grep -q "reaped pid $gone_job (pane %" && pass "the stop is logged with the pane" \
    || fail "no reap line for $gone_job: $(hooks_log | tail -n2)"

  # A failed list-panes is not "no live panes": the server answers, the list
  # does not, the live pane's job stays and the failure is said. $WORK/fails
  # holds how many list-panes calls fail.
  mkdir "$WORK/flaky"
  cat >"$WORK/flaky/tmux" <<STUB
#!/bin/sh
case "\$*" in *list-panes*)
  n=\$(cat "$WORK/fails")
  [ "\$n" -gt 0 ] && { echo \$((n - 1)) >"$WORK/fails"; exit 1; } ;;
esac
exec "$TMUX_BIN" "\$@"
STUB
  chmod +x "$WORK/flaky/tmux"
  flaky_reap() { HOME="$H" PATH="$WORK/flaky:$PATH" "$H/.dotfiles/home/.config/tmux/reap-panes.sh" "$WSOCK" 2>&1; }
  echo 100 >"$WORK/fails"
  out=$(flaky_reap)
  rc=$?
  sleep 1.5
  [ "$rc" -ne 0 ] && [[ "$out" == *"lists no panes"* ]] && kill -0 "$stay_job" 2>/dev/null \
    && pass "a list-panes that keeps failing stops nothing, and says so" \
    || fail "a list-panes that keeps failing: exit $rc, job ${stay_job:-none}, output: $out"
  hooks_log | grep -q 'FAILED to list the panes' && pass "and the failure is logged" \
    || fail "no FAILED line for list-panes: $(hooks_log | tail -n2)"

  # A socket file lost, and a new server on its path: the old server runs on,
  # so its pane's job is not a dead server's, however the new one's sweep reads it.
  mv "$WSOCK" "$WSOCK.away"
  tw -f "$H/.dotfiles/home/.config/tmux/tmux.conf" new-session -d -s w3 -x 120 -y 30 'sleep 300'
  sleep 1.5
  kill -0 "$stay_job" 2>/dev/null && pass "a new server on a lost socket leaves the old server's job" \
    || fail "job ${stay_job:-none} of a live server ended in a new server's sweep"
  tw_stop
  mv "$WSOCK.away" "$WSOCK"

  # The server goes with its last session and no hook is left to run: its
  # job ends at the next server's start.
  tw_stop
  tw -f "$H/.dotfiles/home/.config/tmux/tmux.conf" new-session -d -s w2 -x 120 -y 30 'sleep 300'
  [ -n "$stay_job" ] && ended "$stay_job" && pass "the next server's start ended what the last one left" \
    || fail "job $stay_job outlived its server and the next start"
  tw_stop

  # The start sweep on a server with no session yet: its list-panes fails at
  # first, and the job is stopped all the same. No config, so no sweep but this.
  tw -f /dev/null new-session -d -s w -x 120 -y 30 'sleep 300'
  detached_job "$RETRY" >/dev/null
  retry_job=$(job_of "$RETRY")
  tw_stop
  tw -f /dev/null new-session -d -s w -x 120 -y 30 'sleep 300'
  echo 3 >"$WORK/fails"
  out=$(flaky_reap)
  [ -n "$retry_job" ] && ended "$retry_job" && pass "a list-panes that fails at first is waited for" \
    || fail "job ${retry_job:-none} outlived a reap whose list-panes failed 3 times: $out"
  tw_stop
  pkill -f -- "read -r -t ($GONE|$STAY|$RETRY) " # a failure above leaves them
fi

# --- the log as a whole ---------------------------------------------------------------

odd=$(hooks_log | grep -c -v -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ')
[ "$odd" = 0 ] && pass "every line is UTC-stamped ($(hooks_log | wc -l | tr -d ' ') lines, one file for all the hooks)" \
  || fail "$odd line(s) without a UTC stamp"

log "$failures failure(s)"
[ "$failures" -eq 0 ]

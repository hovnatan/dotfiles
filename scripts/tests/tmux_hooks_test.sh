#!/usr/bin/env bash
#
# tmux_hooks_test.sh -- end-to-end checks for the tmux hooks' log: the hook
# lines of home/.config/tmux/tmux.conf and the scripts they run, in a throwaway tmux
# server and HOME, with a client in a pty that reports focus as a terminal
# does. Needs tmux (3.6 or later, for the focus hooks) and python3; about
# 30 s.
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
#
# Then the window rules, on a second server started from the whole
# home/.config/tmux/tmux.conf, with a client in a pty typing what a terminal would:
#
#   one window, two windows           -> the bar on, on top, "(box) [<session>] |
#                                        cpu N% mem N% | <date time zone>"
#                                        ("box" is the machine's name, from
#                                        its file in the throwaway HOME)
#                                        on the right (a stub
#                                        tmux-mem-cpu-load in the throwaway
#                                        HOME); closing a middle window
#                                        renumbers the rest
#   a machine name of two words, the  -> the line stops with the reason,
#   config's naming line run again       the title is "[<session>]" alone
#   a session of a 40-column name     -> the title cut to 32 columns (an
#                                        80-column client) and "...", the
#                                        clock still drawn
#   status-stats.sh                   -> no tool, or output of another
#                                        form: the reason, exit 1
#   panes setting titles; one that    -> each window named after its
#   sets none                            pane's title, glyph and all, and
#                                        renamed when it changes; the
#                                        titleless one after its program
#   prefix c C n p l w s S C-s 0-9,   -> bound; c new window, C new
#   User0/1                              session, l last window, s the
#                                        session picker
#   Cmd-K Cmd-K Cmd-J (\e[5;30002~,   -> windows 1, 2, 1, nothing typed into
#   \e[5;30001~ as Ghostty sends them)   the pane; in a one-window session
#                                        nothing moves and nothing is shown
#   Shift+Enter as Ghostty sends it   -> CSI 27;2;13~ to a pane that asked
#   under modifyOtherKeys (which tmux    for extended keys (Claude Code
#   asks the terminal for at attach)     does), Enter to any other
#   Ctrl-u, then Ctrl-d, in a plain   -> copy mode half a page up; back at
#   pane                                 the bottom, copy mode gone
#   wheel up, up, down, down          -> copy mode 5 lines up, then 10; back
#                                        at the bottom, copy mode gone
#   click on a window in the bar      -> that window selected
#   Ctrl-click on one                 -> it and the current window swapped
#   prefix k in a pane whose program  -> history and screen both empty (not
#   clears at Ctrl-l                     one screen left in history)
#   prefix / then 123, Enter; q,      -> on line 123 while typing, kept at
#   prefix [, n                          Enter, found again by n
#   in copy mode, g ? 123 and G / 45  -> on 123 and 459 while typing (the
#                                        second from 500, not from where
#                                        the first search started)
#   v, then / 123                     -> the selection kept, up to 123
#   prefix z, z; a drag on the border -> zoomed, unzoomed; the left pane 10
#   10 columns left; prefix x, y         columns narrower; the pane closed
#   prefix L, L after w -> solo -> w  -> solo, then w
#   a bell in a window out of view    -> its label on a yellow background
#   a bell in solo (no client)        -> a yellow " solo:N! " first on the
#                                        right of w's bar, a log line, and
#                                        no message over the bar, and the
#                                        same label on solo's row in the
#                                        session picker; none on
#                                        solo itself; gone once shown. The
#                                        bell in w (its client focused)
#                                        logs "watched"
#   a bell in the window bg's client  -> " bg:0! " on w's bar by @bell
#   shows, its terminal unfocused        (tmux keeps no alert); gone at its
#                                        focus-in
#   the same, bg's client focused but -> unwatched, marked; a key typed in
#   idle past TMUX_WATCHED_STALE_SECONDS bg hides the marker, no focus-in
#   bells in w (out of view), q2, q1, -> prefix C-s from w: w's window, q2,
#   a second apart                       q1, each at the window that rang;
#                                        then, no bell left, back to q2 and
#                                        to q1 (used last, no client on
#                                        them); a session with no bell
#                                        time first
#   prefix C-s with no bell, the one  -> the client goes there
#   other session never attached to
#   prefix C-s with no bell, no other -> the client stays; no message is
#   session                              drawn for either
#   prefix c from window 0 of 3       -> new window at 1, the rest move up
#   prefix S                          -> bar off for that session only, kept
#                                        off while windows come and go;
#                                        prefix S -> back on
#   source-file over the old rule     -> its hooks and per-session values
#   (bar only with 2+ windows)           cleared: the bar on everywhere
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux python3; do
  command -v "$cmd" >/dev/null || {
    echo "tmux_hooks_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/hooktest.XXXXXX)
SOCK="$SOCKDIR/hooks"
TMUX_BIN=$(command -v tmux)

cleanup() {
  [ -n "${client:-}" ] && kill "$client" 2>/dev/null
  [ -n "${bystander:-}" ] && kill "$bystander" 2>/dev/null
  [ -n "${wclient:-}" ] && kill "$wclient" 2>/dev/null
  [ -n "${bgclient:-}" ] && kill "$bgclient" 2>/dev/null
  t kill-server 2>/dev/null
  [ -n "${WSOCK:-}" ] && tw kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  drop_work
}
trap cleanup EXIT

# COPY_BASH: a bash whose copy runs. Panes below run copies of bash under
# other names, since tmux reports a pane's command by its file name. macOS
# kills a copy of a platform binary ("Killed: 9" for /bin/bash), which is
# what `command -v bash` finds when /bin comes before the Nix profile on
# PATH, as in an agent's shell: those panes then died at once, and later
# steps failed or hung on a session that was gone. So the first bash on
# PATH whose copy runs, resolved past links (a copied link target, not a
# copied wrapper).
# A new file per try: macOS remembers the kill for a file overwritten in
# place, and would kill the next copy written over it too.
COPY_BASH=
n=0
for b in $(type -ap bash); do
  n=$((n + 1))
  b=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$b")
  cp "$b" "$SOCKDIR/bash_probe$n" && ("$SOCKDIR/bash_probe$n" -c :) 2>/dev/null && {
    COPY_BASH=$b
    break
  }
done
rm -f "$SOCKDIR"/bash_probe*
[ -n "$COPY_BASH" ] || {
  log "FAIL no bash on PATH runs when copied ($(type -ap bash | paste -sd ' ' -)); macOS kills copies of /bin/bash: put Nix's bash ahead of /bin on PATH"
  exit 1
}

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
log_has() { hooks_log | grep -q -E -- "$1"; }
# wait_for <pattern>: until the log has a line matching it, 5 s at most
wait_for() { until_ok 5 log_has "$1"; }
# attached <t|tw> <session>: a client is on the session
attached() { [ -n "$("$1" list-clients -t "=$2" -F x)" ]; }
# gone <pid>: no such process
gone() { ! kill -0 "$1" 2>/dev/null; }

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

# The client under test, on a: a terminal (pty_client.py) that is sent each
# line written to its fifo as the bytes the line spells.
mkfifo "$WORK/akeys"
python3 "$PTY_CLIENT" "$TMUX_BIN" "$SOCK" "$H" a --keys "$WORK/akeys" &
client=$!

wait_for ' attached [^ ]+ session=a$' \
  && pass "attach is logged" || fail "no attach line: $(hooks_log)"
client_tty=$(t list-clients -t =a -F '#{client_tty}')
# A bystander on b that never reports focus, attached after the client under
# test: it is then the client tmux had last, which is the one a wrong format
# names. With a single client, or with the bystander first, every format
# names the right one.
python3 "$PTY_CLIENT" "$TMUX_BIN" "$SOCK" "$H" b &
bystander=$!
until_ok 5 attached t b || fail "the bystander never attached to b"
bystander_tty=$(t list-clients -t =b -F '#{client_tty}')

# Focus in, out, in, a second apart, as a terminal with focus reporting on
# sends them.
for report in '\x1b[I' '\x1b[O' '\x1b[I'; do
  printf '%s\n' "$report" >"$WORK/akeys"
  sleep 1
done
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
wait_for " session-changed $client_tty session=b\$" \
  && pass "a session switch is logged, naming the client" || fail "no session-changed line: $(hooks_log)"

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
# The machine's name, which the title and the bar lead with
# (scripts/machine_name.sh, asked as the config loads). A fixed short one,
# not this machine's host name: the bar cuts the title at 32 columns here,
# and GitHub's macOS runners are named like "iad20-fj920-<uuid>-<hex>" (70
# characters, no dot), which the bar rightly draws as "(iad20-...".
NAME_FILE="$H/.config/dotfiles/machine-name"
mkdir -p "${NAME_FILE%/*}"
echo box >"$NAME_FILE"
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
  until_ok 5 gone "$pid" || fail "tmux server $pid outlived kill-server by 5 s"
}
stats() { env -i HOME="$H" PATH=/usr/bin:/bin "$H/.dotfiles/home/.config/tmux/status-stats.sh" 2>&1; }
out=$(stats)
rc=$?
[ "$rc" = 0 ] && [ "$out" = "cpu  8%  mem 74%" ] && pass "status-stats.sh labels the tool's numbers: '$out'" \
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

python3 "$PTY_CLIENT" "$TMUX_BIN" "$WSOCK" "$H" w --keys "$WORK/keys" --screen "$WORK/screen" &
wclient=$!
# send_keys <python escapes>: what the terminal would send; tmux handles it at once,
# the pause lets the commands it runs (run-shell -C) finish
send_keys() {
  printf '%s\n' "$1" >"$WORK/keys"
  sleep 0.5
}
until_ok 5 attached tw w || fail "no client attached to w"
# What the client draws on the right: the stub's numbers labelled and
# rounded, then the server's date, time and zone, groups three spaces apart. The numbers are a #() job, so the
# first draw has the date alone (the job still running): wait for a later one.
# The minute by pattern: it may turn between this line and the draw.
stats_clock="cpu  8%  mem 74%   $(tw display -p '%d %b') [0-9]{2}:[0-9]{2} $(tw display -p '%Z')"
want="\(box\) \[w\]   $stats_clock"
until_ok 5 grep -aqE "$want" "$WORK/screen" \
  && pass "the bar draws '$(grep -aoE "$want" "$WORK/screen" | tail -1)' on the right, the machine's name first" \
  || fail "the bar never drew '$want'; screen: $(tr -c '[:print:]' ' ' <"$WORK/screen" | grep -o '[a-z]* [0-9.]*% [^E]*' | tail -2)"
title() { tw display -p -t =w: '#{T:set-titles-string}'; }
[ "$(title)" = "(box) [w]" ] && pass "the terminal's title is '$(title)'" || fail "the terminal's title is '$(title)', not '(box) [w]'"

# The config's naming line, run again as a reload runs it: a name the script
# refuses stops the line with the script's reason, and on a server that has
# no name yet (the option unset, as at its start) the title is the session
# alone. The name put right, the same line brings the lead back.
grep -E "^run-shell -E 'name=.*machine_name\.sh" "$REPO/home/.config/tmux/tmux.conf" >"$WORK/name.conf"
[ "$(wc -l <"$WORK/name.conf" | tr -d ' ')" = 1 ] || fail "home/.config/tmux/tmux.conf has no one line that names the machine"
tw set -gu @machine
echo "two words" >"$NAME_FILE"
out=$(tw source-file "$WORK/name.conf" 2>&1)
rc=$?
[ "$rc" -ne 0 ] && [[ "$out" == *"$NAME_FILE holds 'two words'"* ]] && [ "$(title)" = "[w]" ] \
  && pass "a machine name of two words stops the naming line and says why; the title is '[w]'" \
  || fail "a machine name of two words: exit $rc, title '$(title)', output: $out"
echo box >"$NAME_FILE"
out=$(tw source-file "$WORK/name.conf" 2>&1) && [ "$(title)" = "(box) [w]" ] \
  && pass "the name put right, the naming line leads the title with it again" \
  || fail "after the name was put right: title '$(title)', output: $out"

# A long session name gives way, not the clock: tmux trims status-right from
# its end, so a name left whole would cut the date off instead. The 32
# columns (this client's 80 less 48; 48 on a wide one) hold the "(box) ["
# lead and 25 of the 40 n's.
long=$(printf 'n%.0s' {1..40})
tw new-session -d -s "$long" 'sleep 300'
tw switch-client -t "=$long"
want="\(box\) \[$(printf 'n%.0s' {1..25})\.\.\.   $stats_clock"
until_ok 5 grep -aqE "$want" "$WORK/screen" \
  && pass "a long session name is cut, the clock kept: '$(grep -aoE "$want" "$WORK/screen" | tail -1)'" \
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
cp "$COPY_BASH" "$WORK/cc/notitle"
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
names_are() { [ "$(names)" = "$1" ]; }
wait_names() { until_ok 4 names_are "$1"; }
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
for k in c C n p l w s S C-s 0 1 2 3 4 5 6 7 8 9; do
  [ -n "$(what_key prefix "$k")" ] || missing+=" prefix-$k"
done
for k in User0 User1; do
  [ -n "$(what_key root "$k")" ] || missing+=" $k"
done
[ -z "$missing" ] && pass "window bindings: prefix c C n p l w s S C-s 0-9, User0 User1" || fail "unbound:$missing"
[ -z "$(what_key prefix t)" ] || fail "what_key reads prefix t, which the config leaves unbound, as bound: '$(what_key prefix t)'"
[[ "$(what_key prefix c)" == "new-window -a -c "* ]] && [[ "$(what_key prefix C)" == *"new-session -s "* ]] \
  && [ "$(what_key prefix l)" = last-window ] \
  && [ "$(what_key prefix s)" = 'choose-tree -Zs -F "#{E:@tree_row}" -O activity \; send-keys Down' ] \
  && pass "prefix c: new window, C: new session, l: last window, s: session picker" \
  || fail "prefix c '$(what_key prefix c)', C '$(what_key prefix C)', l '$(what_key prefix l)', s '$(what_key prefix s)'"

# Cmd-J / Cmd-K, as Ghostty sends them. In a one-window session
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
for name in claude 2.1.318 other-program; do cp "$COPY_BASH" "$WORK/named/$name"; done
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

# Shift+Enter. tmux asks the terminal for modifyOtherKeys at attach (CSI > 4 ; 2 m
# with the extkeys feature on xterm*), and Ghostty then sends Shift+Enter as
# CSI 27;2;13~. A pane that asked for the same (Claude Code does, Ext 2) gets it so,
# and takes it as a newline; with extended-keys off it got a plain CR, which
# submits. A pane that did not ask still gets the CR.
shift_enter_reaches() { # <ask>: the bytes a pane gets, having sent <ask> first
  tw new-window -t =w: "printf '$1'; stty raw -echo; cat >\"$WORK/shift_enter_got\""
  sleep 0.5
  send_keys '\x1b[27;2;13~'
  od -An -tx1 "$WORK/shift_enter_got" | tr -d ' \n'
  tw kill-window
}
grep -aqF $'\e[>4;2m' "$WORK/screen" && pass "tmux asks the terminal for modifyOtherKeys 2" \
  || fail "tmux never sent the terminal CSI > 4 ; 2 m"
got=$(shift_enter_reaches '\033[>4;2m')
[ "$got" = 1b5b32373b323b31337e ] && pass "Shift+Enter reaches a pane that asked for extended keys as CSI 27;2;13~" \
  || fail "Shift+Enter in a pane that asked for extended keys sent: $got"
got=$(shift_enter_reaches '')
[ "$got" = 0d ] && pass "Shift+Enter reaches any other pane as Enter" || fail "Shift+Enter in a plain pane sent: $got"

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

# prefix k: the history and the screen both empty afterwards. The pane's
# program clears its screen at Ctrl-l, as a shell does, and tmux scrolls a
# cleared screen into history (scroll-on-clear): history cleared before the
# Ctrl-l kept one screen of it (10 lines of `seq 50` in an 80x10 pane).
cat >"$WORK/clears_at_ctrl_l" <<'EOF'
#!/usr/bin/env bash
seq 500
stty raw -echo
while IFS= read -rsn1 c; do
  [ "$c" = $'\f' ] && printf '\033[H\033[2J'
done
EOF
chmod +x "$WORK/clears_at_ctrl_l"
tw new-window -t =w: "$WORK/clears_at_ctrl_l"
sleep 0.5
before=$(tw display -p -t =w: '#{history_size}')
send_keys '\x01k'
got="$(tw display -p -t =w: '#{history_size}') '$(tw capture-pane -p -t =w: | tr -d ' \n')'"
[ "$before" -gt 0 ] && [ "$got" = "0 ''" ] && pass "prefix k: history ($before lines) and screen both cleared" \
  || fail "prefix k: history before $before; after it, history and screen: $got"
tw kill-window

# prefix /: incremental search up. Each key typed moves to the nearest match,
# before any Enter: "123" typed -> the cursor on line 123 already; Enter keeps
# it there. Later, after q, prefix [ then n runs that search again.
tw new-window -t =w: "seq 500; exec sleep 100"
sleep 0.5
send_keys '\x01/'
send_keys '123'
a=$(tw display -p -t =w: '#{pane_in_mode} #{copy_cursor_line}')
send_keys '\r'
b=$(tw display -p -t =w: '#{pane_in_mode} #{copy_cursor_line}')
send_keys 'q'
send_keys '\x01['
send_keys 'n'
c=$(tw display -p -t =w: '#{pane_in_mode} #{copy_cursor_line}')
[ "$a|$b|$c" = "1 123|1 123|1 123" ] \
  && pass "prefix /: on line 123 as '123' is typed, kept at Enter, and found again by prefix [, n" \
  || fail "prefix /: mode and cursor line typing '123' '$a', at Enter '$b', prefix [ n '$c'; wanted '1 123' each"

# The same inside copy mode, where ? searches down and / up (vi's swapped):
# from the top (g), ? then "123" is on line 123 before any Enter; from the
# bottom (G), / then "45" is on 459, the nearest match above 500.
send_keys 'g'
send_keys '?'
send_keys '123'
a=$(tw display -p -t =w: '#{copy_cursor_line}')
send_keys '\r'
send_keys 'G'
send_keys '/'
send_keys '45'
b=$(tw display -p -t =w: '#{copy_cursor_line}')
send_keys '\r'
[ "$a|$b" = "123|459" ] && pass "copy mode ? and /: on the match while typing, down and up" \
  || fail "copy mode: ? then 123 on '$a', wanted 123; / then 45 on '$b', wanted 459"

# A selection begun with v and not yet moved is kept by a search, which
# extends it to the match: the search's clear-selection is skipped.
send_keys 'G'
send_keys 'k'
send_keys 'v'
send_keys '/'
send_keys '123'
got=$(tw display -p -t =w: '#{copy_cursor_line} #{selection_present}')
send_keys '\r'
[ "$got" = "123 1" ] && pass "v then /: the selection kept, reaching the match" \
  || fail "v then / 123: cursor line and selection '$got', wanted '123 1'"
tw kill-window

# Panes: in a window split left | right, prefix z zooms the current pane and
# back; a drag on the border between them (SGR press, motion with button 1
# held, release; the bar takes row 1) resizes them; prefix x asks, and y
# closes the current pane.
tw new-window -t =w: 'sleep 100'
tw split-window -h -t =w: 'sleep 100'
sleep 0.3
send_keys '\x01z'
a=$(tw display -p -t =w: '#{window_zoomed_flag}')
send_keys '\x01z'
b=$(tw display -p -t =w: '#{window_zoomed_flag}')
[ "$a $b" = "1 0" ] && pass "prefix z zooms the pane, and again unzooms" || fail "prefix z, z: zoomed flag $a $b, wanted 1 0"
left_w=$(tw display -p -t =w:.0 '#{pane_width}')
border=$(($(tw display -p -t =w:.0 '#{pane_right}') + 2)) # 0-based right edge -> 1-based border column
send_keys "\\x1b[<0;$border;10M"
send_keys "\\x1b[<32;$((border - 10));10M"
send_keys "\\x1b[<0;$((border - 10));10m"
got=$(tw display -p -t =w:.0 '#{pane_width}')
[ "$got" = "$((left_w - 10))" ] && pass "dragging the pane border 10 columns left: left pane $left_w -> $got wide" \
  || fail "border drag: left pane $left_w -> $got wide, wanted $((left_w - 10))"
send_keys '\x01x'
send_keys 'y'
got=$(tw display -p -t =w: '#{window_panes}')
[ "$got" = 1 ] && pass "prefix x, y: the pane closed" || fail "prefix x, y: $got panes, wanted 1"
tw kill-window

# prefix L flips the client back to the session it showed before, and again.
cname=$(tw list-clients -t =w -F '#{client_name}')
tw switch-client -c "$cname" -t =solo
tw switch-client -c "$cname" -t =w
send_keys '\x01L'
a=$(tw display -p -c "$cname" '#{client_session}')
send_keys '\x01L'
b=$(tw display -p -c "$cname" '#{client_session}')
[ "$a $b" = "solo w" ] && pass "prefix L, L: sessions solo, w" || fail "prefix L, L: sessions $a $b, wanted solo w"

# prefix s opens the picker one row below the client's own session: Enter
# alone goes to the session used before it, solo.
send_keys '\x01s'
send_keys '\r'
a=$(tw display -p -c "$cname" '#{client_session}')
[ "$a" = solo ] && pass "prefix s, Enter: the session used before this one, solo" \
  || fail "prefix s, Enter: session $a, wanted solo; sessions: $(tw list-sessions -F '#{session_name}=#{session_activity}' | paste -sd ' ' -)"
tw switch-client -c "$cname" -t =w

# A bell in a window out of view: its label is drawn on a yellow background (#d79921, as
# the RGB parameters the client is sent).
tw new-window -d -t =w: "printf '\\a'; exec sleep 100"
sleep 0.5
grep -aq '48;2;215;153;33' "$WORK/screen" && pass "a bell paints its window's label yellow in the bar" \
  || fail "no yellow background drawn; flags: $(tw list-windows -t =w -F '#{window_index}:#{window_bell_flag}' | tr '\n' ' ')"

# A bell in solo, which no client is attached to (bell-elsewhere.sh): the
# bar of the client on w gets a yellow marker and the log a line. The
# window's name holds "#S" (-n expands formats, hence ##S), which the log
# has as typed: the hook's run-shell line expands formats once, not twice.
wname=$(tw list-clients -t =w -F '#{client_name}')
ring=$(tw new-window -d -P -F '#{window_index}' -t =solo: -n 'ring ##S' "printf '\\a'; exec sleep 100")
[ "$(tw display -p -t "=solo:$ring" '#{window_name}')" = 'ring #S' ] \
  || fail "the ringing window is named '$(tw display -p -t "=solo:$ring" '#{window_name}')', not 'ring #S'"
wait_for " bell session=solo window=$ring \(ring #S\): unwatched \(no client attached\), marked$" \
  && pass "a bell in a session with no client is logged as unwatched and marked" \
  || fail "no bell line for solo:$ring: $(hooks_log | tail -3)"
# The marker is the whole notice: no message is put over w's bar (one "bell:
# solo:N <name>" for 5 s, until 2026-11-19). The log line above is the
# script's last act, so a message would have been sent by now; the wait is
# for the client to draw the marker, after which a message would be drawn too.
until_ok 5 grep -aqF " solo:$ring! " "$WORK/screen" && ! grep -aqF "bell: solo:" "$WORK/screen" \
  && pass "w's client draws the marker ' solo:$ring! ' and no 'bell: solo:...' message" \
  || fail "w's client drew: marker $(grep -acF " solo:$ring! " "$WORK/screen") time(s), message '$(grep -aoF "bell: solo:$ring ring #S" "$WORK/screen" | head -1)'"
# @bell_marker as tmux expands it for that client: the marker in the bell
# yellow, and it first in status-right, before the session's name.
# list-clients, not display -p -c: display uses -c's client for formats only
# when it is on the target session, by default the latest active client's,
# so with a second client in bg it expanded bg's bar (#{client_session} bg).
left() { tw list-clients -f "#{==:#{client_name},$wname}" -F '#{E:@bell_marker}'; }
no_marker() { [ -z "$(left)" ]; }
right() { tw list-clients -f "#{==:#{client_name},$wname}" -F '#{E:status-right}'; }
want="#[fg=#282828,bg=#d79921] solo:$ring! #[default] "
[ "$(left)" = "$want" ] && pass "w's bell marker marks solo: '$(left)'" \
  || fail "w's bell marker is '$(left)', wanted '$want'"
row=$(tw list-sessions -f '#{==:#{session_name},solo}' -F '#{E:@tree_row}')
[ "$row" = "#[fg=#282828,bg=#d79921] $ring! #[default] #[fg=themelightgrey]$(tw display -p -t =solo: '#{session_windows}') windows" ] \
  && pass "the session picker's row for solo carries the bell label: '$row'" \
  || fail "the session picker's row for solo is '$row'"
case $(right) in
  "${want} (box) [w]   "*) pass "the marker opens status-right, before ' (box) [w]'" ;;
  *) fail "status-right on w is '$(right)', wanted it to start '${want} (box) [w]   '" ;;
esac
# The bell rang in w as well (the step above), whose client has focus (tmux
# counts a client focused from its attach until its terminal says otherwise)
# and typed a moment ago: watched, logged with that evidence, nothing marked.
w_bell=$(hooks_log | grep ' bell session=w ')
grep -qE ": watched \(${wname#/dev/} focused, input [0-9]+s ago\)$" <<<"$w_bell" \
  && pass "a bell in a session whose client has focus and fresh input is logged as watched: '${w_bell#* }'" \
  || fail "the bell in w, its client focused, logged '$w_bell'"
# On solo itself solo's marker is left out (its window label shows the
# bell), while w's, from the bell in w above, now shows; shown, the window's
# alert clears, and w's marker is empty again.
tw switch-client -c "$wname" -t =solo
case $(left) in *" solo:"*) false ;; *" w:"*) true ;; *) false ;; esac \
  && [ -n "$(tw display -p -t =solo: '#{session_alerts}')" ] \
  && pass "a client on solo marks w's bell, not solo's own: '$(left)'" \
  || fail "on solo: bell marker '$(left)', solo's alerts '$(tw display -p -t =solo: '#{session_alerts}')'"
tw select-window -t "=solo:$ring"
tw switch-client -c "$wname" -t =w
# The switch's set-option -qu @bell waits behind client-session-changed[0],
# focus-out-unattached.sh, which runs without -b: the marker clears a moment
# after the switch returns, not at once.
until_ok 5 no_marker && pass "once the window was shown, the marker is gone" \
  || fail "after showing solo:$ring: bell marker '$(left)'"
tw kill-window -t "=solo:$ring"

# A bell in a window with an empty name (a pane title Claude Code cleared,
# under automatic-rename): #{q:} of an empty value expands to nothing, not
# '', and the hook once passed the script 4 arguments: "returned 2". Then
# @bell is unset by hand, as no client looks at solo to clear it.
ring=$(tw new-window -d -P -F '#{window_index}' -t =solo: -n '' "printf '\\a'; exec sleep 100")
wait_for " bell session=solo window=$ring \(\): unwatched \(no client attached\), marked$" \
  && pass "a bell in a window with an empty name is logged and marked" \
  || fail "no bell line for solo:$ring, named '': $(hooks_log | tail -3); messages: $(tw show-messages | tail -3)"
tw kill-window -t "=solo:$ring"
tw set-option -u -t =solo: @bell
tw set-option -u -t =solo: @bell_at

# A bell in the window an unfocused client shows: a second terminal on
# session bg, its tab in the background (focus out). tmux keeps no alert of a
# bell in a shown window, so the marker is @bell's; the client's focus-in
# clears it. Each line written to $WORK/bgkeys is sent as the bytes it spells.
tw new-session -d -s bg 'sleep 300'
mkfifo "$WORK/bgkeys"
python3 "$PTY_CLIENT" "$TMUX_BIN" "$WSOCK" "$H" bg --keys "$WORK/bgkeys" &
bgclient=$!
until_ok 5 attached tw bg || fail "no client attached to bg"
bgname=$(tw list-clients -t =bg -F '#{client_name}')
bg_flags() { tw list-clients -t =bg -F '#{client_flags}'; }
bg_unfocused() { case ,$(bg_flags), in *,focused,*) return 1 ;; esac }
printf '%s\n' '\x1b[O' >"$WORK/bgkeys"
until_ok 5 bg_unfocused
tw respawn-pane -k -t =bg: "printf '\\a'; exec sleep 100"
wait_for " bell session=bg window=0 \([^)]*\): unwatched \(${bgname#/dev/} not focused, input [0-9]+s ago\), marked$" \
  && pass "a bell where bg's unfocused client looks is logged as unwatched and marked" \
  || fail "no bell line for bg:0 (bg's client flags: $(bg_flags)): $(hooks_log | tail -3)"
want="#[fg=#282828,bg=#d79921] bg:0! #[default] "
[ "$(left)" = "$want" ] && [ -z "$(tw display -p -t =bg: '#{session_alerts}')" ] \
  && pass "w's bell marker marks bg by @bell, tmux holding no alert: '$(left)'" \
  || fail "w's bell marker is '$(left)', wanted '$want'; bg's alerts '$(tw display -p -t =bg: '#{session_alerts}')', @bell '$(tw show -t =bg: -qv @bell)'; clients: $(tw list-clients -F '#{client_name} on #{client_session}' | paste -sd ' ' -); sessions: $(tw list-sessions -F '#{session_name}=#{session_id}@bell[#{@bell}]alerts[#{session_alerts}]' | paste -sd ' ' -)"
printf '%s\n' '\x1b[I' >"$WORK/bgkeys"
until_ok 5 no_marker && [ -z "$(tw show -t =bg: -qv @bell)" ] \
  && pass "bg's client focused again: the marker is gone" \
  || fail "after bg's focus-in: w's bell marker '$(left)', bg's @bell '$(tw show -t =bg: -qv @bell)'"

# Focus gone stale (scripts/tmux_watched.sh's rule): bg's client
# still says focused, as a locked Mac's terminal does, but has had no input for longer than
# TMUX_WATCHED_STALE_SECONDS (1 s here, from the server's environment, which run-shell
# passes on): unwatched. Then a key typed there, its focus flag unchanged as
# when a terminal's focus reports stopped, so no focus-in clears @bell: the
# marker hides by the input alone (@bell_at older than #{session_activity}).
tw set-environment -g TMUX_WATCHED_STALE_SECONDS 1
sleep 2
tw respawn-pane -k -t =bg: "printf '\\a'; exec sleep 100"
wait_for " bell session=bg window=0 \([^)]*\): unwatched \(${bgname#/dev/} focused, input [0-9]+s ago\), marked$" \
  && pass "a focused client with no input past TMUX_WATCHED_STALE_SECONDS leaves its session unwatched" \
  || fail "no stale-focus bell line for bg (bg's client flags: $(bg_flags)): $(hooks_log | tail -3)"
[ "$(left)" = "$want" ] && pass "and w's bell marker marks bg: '$(left)'" \
  || fail "after the stale-focus bell: w's bell marker '$(left)', wanted '$want'"
sleep 1.1 # input in a later second than @bell_at: the compare is by the second
printf '%s\n' 'x' >"$WORK/bgkeys"
until_ok 5 no_marker && [ "$(tw show -t =bg: -qv @bell)" = '0!' ] \
  && pass "a key typed in bg hides the marker, @bell still set (no focus-in came)" \
  || fail "after a key in bg: w's bell marker '$(left)', bg's @bell '$(tw show -t =bg: -qv @bell)'"
tw set-environment -gu TMUX_WATCHED_STALE_SECONDS
kill "$bgclient"
wait "$bgclient" 2>/dev/null
bgclient=
tw kill-session -t =bg

# prefix C-s (bell-next.sh). Three bells a second apart (the times are by
# the second): in w, the client's own session, in a window out of view
# ("watched", so held by tmux's alert alone), then in q2, then in q1. The
# order is by time, not by name (q1 lists first). w's earlier alerts are
# shown first, so w holds this bell alone.
wcur=$(current w)
for i in $(tw list-windows -t =w -f '#{window_bell_flag}' -F '#{window_index}'); do
  tw select-window -t "=w:$i"
done
tw select-window -t "=w:$wcur"
tw new-session -d -s q1 'sleep 300'
tw new-session -d -s q2 'sleep 300'
# ring_in <session> <window name> <the log line's verdict>: a new window out
# of view rings, and its index is in $rang once the hook has logged it
ring_in() {
  rang=$(tw new-window -d -P -F '#{window_index}' -t "=$1:" -n "$2" "printf '\\a'; exec sleep 100")
  wait_for " bell session=$1 window=$rang \($2\): $3" || fail "no bell line for $1:$rang ($2): $(hooks_log | tail -3)"
}
unwatched='unwatched .*, marked$'
where() { tw list-clients -f "#{==:#{client_name},$wname}" -F '#{client_session}:#{window_index}'; }
held() { tw list-sessions -F '#{session_name}=#{E:@bell_held}' | paste -sd ' ' -; }
ring_in w next-w 'watched '
rw=$rang
sleep 1.1
ring_in q2 next-q2 "$unwatched"
r2=$rang
sleep 1.1
ring_in q1 next-q1 "$unwatched"
r1=$rang
[ "$(held)" = "q1=$r1! q2=$r2! solo= w=$rw!" ] || fail "before prefix C-s the sessions hold '$(held)', wanted 'q1=$r1! q2=$r2! solo= w=$rw!'"
# next_bell <where the client lands> <the log line's end>: press prefix C-s
next_bell() {
  send_keys '\x01\x13'
  wait_for " bell-next ${wname#/dev/}: $2\$" && [ "$(where)" = "$1" ] \
    && pass "prefix C-s: $1 ($2)" \
    || fail "prefix C-s: the client is on $(where), wanted $1; log: $(hooks_log | grep ' bell-next ' | tail -2); held: $(held)"
}
next_bell "w:$rw" "-> w:$rw \(rang [0-9]+s ago, 3 held\)"
next_bell "q2:$r2" "-> q2:$r2 \(rang [0-9]+s ago, 2 held\)"
# q2 is used a second after w, for the way back below.
sleep 1.1
next_bell "q1:$r1" "-> q1:$r1 \(rang [0-9]+s ago, 1 held\)"
next_bell "q2:$r2" "no bell held, -> q2 \(used [0-9]+s ago\)"
next_bell "q1:$r1" "no bell held, -> q1 \(used [0-9]+s ago\)"
# A session that holds a bell with no time (its hook not yet done) goes
# first, though solo rings after q2 here.
ring_in q2 next-q2b "$unwatched"
r2=$rang
ring_in solo next-solo "$unwatched"
rs=$rang
tw set-option -u -t =solo: @bell_at
next_bell "solo:$rs" "-> solo:$rs \(rang at a time not recorded, 2 held\)"
next_bell "q2:$r2" "-> q2:$r2 \(rang [0-9]+s ago, 1 held\)"
tw switch-client -c "$wname" -t =w
tw kill-window -t "=w:$rw"
tw select-window -t "=w:$wcur"
tw kill-session -t =q1
tw kill-session -t =q2
# A session never attached to is one to go to as well: a new solo, the one
# other session. With it gone there is nowhere to go.
tw kill-session -t =solo
tw new-session -d -s solo 'sleep 300'
next_bell "solo:0" "no bell held, -> solo \(used [0-9]+s ago\)"
tw switch-client -c "$wname" -t =w
tw kill-session -t =solo
next_bell "w:$wcur" "no bell held, and no detached session to go to"
grep -aqF "no bell held" "$WORK/screen" && fail "a 'no bell held' message was drawn for the client" \
  || pass "with no bell held, no message is drawn: the log has it"

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

# reap-panes-macos.sh by way of the real hooks. The job is a bash that is not
# an Apple binary, whose environment ps would hide: COPY_BASH, as macOS lets
# only those run copied (`command -v bash` can be /bin/bash). Its parent
# exits, so it is detached. Each carries a number of its own, to be found by.
if [ "$(uname)" = Darwin ]; then
  BASH_BIN=$COPY_BASH
  GONE=$((300000 + $$ % 100000)) STAY=$((GONE + 100000)) RETRY=$((GONE + 200000)) # numbers no other run holds
  # detached_job <timeout>: a pane that leaves a job behind and idles; prints
  # the pane's id.
  detached_job() {
    tw new-window -d -P -F '#{pane_id}' -t =w: \
      "sh -c '(nohup $BASH_BIN -c \"read -r -t $1 <>$WORK/never\" </dev/null >/dev/null 2>&1 &) ; exec sleep 300'"
  }
  job_of() { # <timeout>: the job's pid, once it is up. Anchored: the pane's
    # own sh -c line holds the same words until it execs.
    until_ok 3 pgrep -f -- "^$BASH_BIN -c read -r -t $1 "
  }
  ended() { until_ok 6 gone "$1"; } # <pid>: true once it has exited, within 6 s

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

finish

#!/usr/bin/env bash
# check.sh covers: scripts/claude_manager_start.sh scripts/lib/* home/.config/systemd/user/claude-tmux.service home/.profile.shared home/.config/tmux/reap-panes.sh home/.tmux.conf
# check.sh runs-on: Linux
#
# claude_tmux_test.sh -- end-to-end checks of the manager's boot start and of
# the reap of what closed panes leave, on a real tmux server and real systemd
# scopes, with a stub claude. Safe beside live sessions: every server here
# lives under a TMUX_TMPDIR of its own, so `tmux` means the throwaway one.
#
#   the unit's ExecStart line  -> claude_manager_start.sh -> "manager", window 0
#   a pane closes              -> tmux hook -> reap-panes.sh -> its scope stopped
#
# Needs a user systemd manager:
#   XDG_RUNTIME_DIR=/run/user/$(id -u) scripts/tests/claude_tmux_test.sh
set -u

[ "$(uname)" = Linux ] || {
  echo "claude_tmux_test.sh: Linux only (needs systemd --user)" >&2
  exit 1
}
for cmd in tmux fish systemd-run systemctl getent; do
  command -v "$cmd" >/dev/null || {
    echo "claude_tmux_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done
[ -n "${XDG_RUNTIME_DIR:-}" ] || {
  echo "claude_tmux_test.sh: XDG_RUNTIME_DIR is unset; run it from a login with a user systemd session (export XDG_RUNTIME_DIR=/run/user/\$(id -u))" >&2
  exit 1
}

REPO=$(cd "$(dirname "$0")/../.." && pwd)
UNIT="cttest-$$"
WORK=$(mktemp -d)
# Not under $WORK: a socket path has about 100 characters to live in. Every
# `tmux` below rests on these lines: an empty TMUX_TMPDIR, or a TMUX left by a
# pane this runs in (the pre-push hook can), would mean the live server.
TMUX_TMPDIR=$(mktemp -d /tmp/cttest.XXXXXX) || exit 1
export TMUX_TMPDIR
unset TMUX TMUX_PANE
H="$WORK/home"
LOGIN_SHELL=$(getent passwd "$(id -un)" | cut -d: -f7)
SOCKPATH="$TMUX_TMPDIR/tmux-$(id -u)/default"
MANAGER_DIR="$H/.dotfiles/claude_tmux_session"
TRANSCRIPTS="$H/.claude/projects/${MANAGER_DIR//[^a-zA-Z0-9]/-}"

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
# The test's servers read the real config, with ~ the throwaway HOME: the
# hooks are what is under test.
t() { HOME="$H" tmux "$@"; }
reap() { HOME="$H" "$REPO/home/.config/tmux/reap-panes.sh" "$@"; }

# unit_value <key>: the value of the unit file's one <key>= line; a key missing
# or set twice ends the run, as it would no longer test what systemd runs.
unit_value() {
  local v
  v=$(sed -n "s/^$1=//p" "$REPO/home/.config/systemd/user/claude-tmux.service")
  [ -n "$v" ] && [ "$(wc -l <<<"$v")" = 1 ] || {
    echo "the unit file has no single $1= line: '$v'" >&2
    exit 1
  }
  echo "$v"
}

# orphan_in <session> [<window to split>] [<tmux command>]: a new pane whose
# program leaves a job behind (setsid, as a tool's background job is) and then
# idles; prints "<orphan pid> <pane id>".
ORPHAN=$((300000 + $$ % 100000)) # a sleep length nothing else on the box runs
orphan_in() {
  # Earlier orphans run the same command: wait for one that was not there.
  local before p pane tm=${3:-t} cmd="sh -c 'setsid sleep $ORPHAN </dev/null >/dev/null 2>&1 & exec sleep 100000'"
  before=" $(pgrep -f -x "sleep $ORPHAN" | tr '\n' ' ')"
  if [ -n "${2:-}" ]; then
    pane=$($tm split-window -d -P -F '#{pane_id}' -t "$2" "$cmd")
  else
    pane=$($tm new-window -d -P -F '#{pane_id}' -t "=$1:" "$cmd")
  fi
  for _ in $(seq 20); do
    for p in $(pgrep -f -x "sleep $ORPHAN"); do
      case $before in *" $p "*) ;; *) echo "$p $pane" && return ;; esac
    done
    sleep 0.1
  done
}
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; } # not `kill -0 0`: that succeeds
# gone <pid>: true once it has exited, within 5 s.
gone() {
  for _ in $(seq 50); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}
# claude_of <session> [<window>]: the pid of the claude under the shell of that
# window, 0 by default, once up.
claude_of() {
  local shell_pid pid
  for _ in $(seq 100); do
    shell_pid=$(t display -p -t "=$1:${2:-0}" '#{pane_pid}' 2>/dev/null)
    pid=$(pgrep -P "${shell_pid:-0}" -x claude) && echo "$pid" && return
    sleep 0.1
  done
  return 1
}
# stop_server: end the default server and wait for it, as the next client
# would otherwise reach a dying one.
stop_server() {
  local pid
  pid=$(t display -p '#{pid}' 2>/dev/null) || return 0
  t kill-server
  gone "$pid" || fail "server $pid outlived kill-server by 5 s"
}

cleanup() {
  systemctl --user stop "$UNIT" 2>/dev/null
  systemctl --user reset-failed "$UNIT" 2>/dev/null
  for name in default other hand nested; do
    tmux -L "$name" kill-server 2>/dev/null
  done
  pkill -f -x "sleep $ORPHAN"
  # A hook still running writes under $H; the servers' sockets are here.
  for _ in $(seq 50); do
    pgrep -f "$WORK" >/dev/null || break
    sleep 0.1
  done
  rm -rf "$TMUX_TMPDIR"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# --- throwaway HOME ---------------------------------------------------------

# The stub must win over the real claude on every PATH a login shell builds, or
# the manager below would resume a real conversation. Its idle process is a copy
# of bash named claude, waiting on a FIFO nobody writes. Not a copy of sleep:
# Ubuntu 26.04's is uutils' multi-call binary, which runs under its own name only.
mkdir -p "$H/.local/bin" "$H/.claude/projects" "$WORK/idle"
# ~/.dotfiles holds the repo, entry by entry, so the hooks and scripts that name
# ~/.dotfiles/... run this checkout -- but a .logs of its own, out of the one
# the live server writes to.
mkdir "$H/.dotfiles"
for e in "$REPO"/* "$REPO"/.[!.]*; do
  [ "${e##*/}" = .logs ] || ln -s "$e" "$H/.dotfiles/"
done
# The real Nix profile, so login shells here pick the tmux the service does:
# the distro's (3.4 on Ubuntu 24.04) makes no scope per pane, and the checks
# below would have nothing to test.
[ -e "$HOME/.nix-profile" ] && ln -s "$(readlink -f "$HOME/.nix-profile")" "$H/.nix-profile"
cp "$(command -v bash)" "$WORK/idle/claude"
mkfifo "$WORK/idle/never"
cat >"$H/.local/bin/claude" <<STUB
#!/bin/bash
echo "\$* " >"$WORK/args.\$\$"
exec "$WORK/idle/claude" -c "read -r -t 100000 <>'$WORK/idle/never'"
STUB
chmod +x "$H/.local/bin/claude"

# ~/.profile as setup_user_symlinks.sh appends it.
cat >"$H/.profile" <<'PROFILE'
if [ -f "$HOME/.dotfiles/home/.profile.shared" ]; then
  . "$HOME/.dotfiles/home/.profile.shared"
fi
PROFILE
ln -s "$REPO/home/.tmux.conf" "$H/.tmux.conf"

resolved=$(env -i HOME="$H" USER="$USER" PATH=/usr/bin:/bin "$LOGIN_SHELL" -lc 'command -v claude')
if [ "$resolved" != "$H/.local/bin/claude" ]; then
  log "ABORT: a login shell in the throwaway HOME resolves claude to '$resolved', not the stub"
  failures=1
  exit 1
fi
log "work dir $WORK, tmux dir $TMUX_TMPDIR, login shell $LOGIN_SHELL"

# --- the boot start, from the unit's own lines ------------------------------

# The unit's ExecStart with systemd's %h filled in, and the keys that decide
# how it runs: a transient unit of those is what systemd runs at boot.
start_script=$(unit_value ExecStart) || exit 1
start_script=$(sed -n "s/^\/bin\/sh -c '\(.*\)'\$/\1/p" <<<"$start_script")
[ -n "$start_script" ] || {
  log "ABORT: ExecStart is not /bin/sh -c '...'"
  failures=1
  exit 1
}
start_script=${start_script//%h/$H}
props=()
for key in Type RemainAfterExit KillMode; do
  val=$(unit_value "$key") || exit 1
  props+=(-p "$key=$val")
done
start_unit() {
  systemd-run --user --quiet --unit="$UNIT" "${props[@]}" \
    -E HOME="$H" -E SHELL="$LOGIN_SHELL" -E TMUX_TMPDIR="$TMUX_TMPDIR" /bin/sh -c "$start_script"
}

if start_unit && t has-session -t =manager 2>/dev/null; then pass "the unit brings up session manager"; else
  fail "session manager never appeared"
  exit 1
fi
state=$(systemctl --user show "$UNIT" -p ActiveState -p SubState --value | paste -sd ' ' -)
[ "$state" = "inactive dead" ] && pass "the unit: $state once start returned" || fail "the unit after start: '$state'"

# Until it execs the shell, a new pane's process is a fork of the server, named
# "tmux: server": the unit returning does not mean the shell has started.
shell_pid=$(t display -p -t =manager:0 '#{pane_pid}')
for _ in $(seq 50); do
  [ "$(ps -o comm= -p "$shell_pid")" = fish ] && break
  sleep 0.1
done
read -r pane_cmd pane_dir < <(t display -p -t =manager:0 '#{pane_current_command} #{pane_current_path}')
[ "$(ps -o comm= -p "$shell_pid")" = fish ] && pass "window 0 runs a shell ($pane_cmd)" \
  || fail "window 0 runs $(ps -o comm= -p "$shell_pid")"
[ "$(readlink -f "$pane_dir")" = "$(readlink -f "$MANAGER_DIR")" ] && pass "in the session folder" \
  || fail "window 0 is in $pane_dir"
if c1=$(claude_of manager); then pass "claude (pid $c1) is the shell's child"; else
  fail "no claude under window 0's shell: $(t capture-pane -p -t =manager:0 | tail -n5)"
  exit 1
fi
args=$(cat "$WORK/args.$c1")
[ "$args" = "-n $(hostname)/manager --dangerously-skip-permissions " ] \
  && pass "typed with its name and permission mode" || fail "claude's args: $args"
[ "$(t list-windows -t =manager: -F '#W' | wc -l)" = 1 ] && pass "no folder named, no Remote Control window" \
  || fail "windows with no folder named: $(t list-windows -t =manager: -F '#W' | tr '\n' ' ')"

on_exit=$(t show -gv remain-on-exit)
[ "$on_exit" = off ] && pass "remain-on-exit off with home/.tmux.conf loaded" || fail "remain-on-exit is '$on_exit'"
server=$(t display -p '#{pid}')
cgroup=$(cat "/proc/$server/cgroup")
[[ "$cgroup" == */run-*.scope ]] && pass "the server is in a scope of its own: ${cgroup##*/}" \
  || fail "the server's cgroup: $cgroup"

# Stopping or starting the unit leaves what runs, and a claude that quit leaves
# its shell, the session with it.
systemctl --user stop "$UNIT" 2>/dev/null
kill -0 "$c1" 2>/dev/null && pass "stopping the unit leaves the session" || fail "stopping the unit ended claude"
start_unit
[ "$(claude_of manager)" = "$c1" ] && pass "a second start leaves the running claude" \
  || fail "after a second start: claude $(claude_of manager), was $c1"
kill "$c1"
gone "$c1" || fail "claude $c1 ignored TERM"
sleep 0.3
t has-session -t =manager 2>/dev/null && [ "$(t display -p -t =manager:0 '#{pane_pid}')" = "$shell_pid" ] \
  && pass "claude quitting leaves the shell and the session" || fail "claude quit and the session went"
start_unit
sleep 0.5
pgrep -P "$shell_pid" -x claude >/dev/null && fail "a start typed into a session it should leave alone" \
  || pass "a start leaves a session whose claude quit"

# An earlier conversation and a server gone: the next start is cold, and new.
mkdir -p "$TRANSCRIPTS"
echo '{}' >"$TRANSCRIPTS/some-id.jsonl"
stop_server
start_unit
if c2=$(claude_of manager); then
  [ "$(cat "$WORK/args.$c2")" = "$args" ] && pass "a cold start beside a transcript starts a new conversation" \
    || fail "a cold start beside a transcript: $(cat "$WORK/args.$c2")"
else
  fail "no claude after a cold start"
  exit 1
fi

# The Remote Control window, on a machine that names a folder. Its file stays
# for the rest of the run: the checks below see a session of two windows. A file
# naming no folder stops the start, before anything opens.
RC_FILE="$H/.config/claude-tmux/remote-control-dir"
mkdir -p "${RC_FILE%/*}" "$WORK/rc"
stop_server
for bad in "$WORK/no-such-folder" "relative/folder"; do
  echo "$bad" >"$RC_FILE"
  out=$(HOME="$H" PATH="$H/.local/bin:$PATH" "$REPO/scripts/claude_manager_start.sh" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"$RC_FILE holds '$bad'"* ]] && ! t has-session -t =manager 2>/dev/null \
    && pass "a file holding $bad stops the start and says so" \
    || fail "a file holding $bad: exit $rc, sessions '$(t ls 2>&1)', output: $out"
done
echo "$WORK/rc" >"$RC_FILE"
start_unit
if c3=$(claude_of manager remote-control); then
  [ "$(cat "$WORK/args.$c3")" = "remote-control --spawn=same-dir --name $(hostname)/remote-control " ] \
    && pass "window remote-control runs claude remote-control under its shell" \
    || fail "the Remote Control window's args: $(cat "$WORK/args.$c3")"
else
  fail "no claude in window remote-control: $(t list-windows -t =manager: -F '#I #W' | tr '\n' ';')"
fi
rc_path=$(t display -p -t =manager:remote-control '#{pane_current_path}')
[ "$(readlink -f "$rc_path")" = "$(readlink -f "$WORK/rc")" ] && pass "in the machine's folder" \
  || fail "window remote-control is in $rc_path"
[ "$(t display -p -t =manager: '#{window_index}')" = 0 ] && pass "and the session stays on window 0" \
  || fail "the session's current window is $(t display -p -t =manager: '#{window_name}')"
claude_of manager >/dev/null && pass "window 0 has its claude beside it" || fail "no claude in window 0 beside remote-control"

# --- what a closed pane left ------------------------------------------------

# A process a session detached (setsid, nohup, a tool's background job)
# outlives its pane in that scope; the hooks stop that scope, here for each way
# a pane closes.
t new-session -d -s cl1 sleep 100000
t new-session -d -s cl2 sleep 100000
read -r o1 _ < <(orphan_in cl1)
read -r o2 _ < <(orphan_in cl2)
t kill-session -t =cl1
if [ -n "$o1" ] && gone "$o1"; then pass "closing a session stops what it left in the background (pid $o1)"; else
  fail "pid ${o1:-none} outlived its session cl1 ($(ps -o args= -p "${o1:-0}"))"
fi
alive "${o2:-}" && pass "and leaves another session's (pid $o2) running" \
  || fail "closing cl1 also ended cl2's background job (pid ${o2:-none})"

read -r o pane < <(orphan_in cl2)
kill "$(t display -p -t "$pane" '#{pane_pid}')" # its program exits: pane-exited
gone "${o:-0}" && pass "a pane whose program exits: its orphan (pid $o) stopped" \
  || fail "a pane whose program exited left its orphan (pid ${o:-none}) running"

# A window of two orphan panes: kill-pane closes one (after-kill-pane, the
# window kept), kill-window the other (window-unlinked).
read -r o_a pane_a < <(orphan_in cl2)
w=$(t display -p -t "$pane_a" '#{window_id}')
read -r o_b pane_b < <(orphan_in cl2 "$w")
t kill-pane -t "$pane_b"
gone "${o_b:-0}" && alive "${o_a:-}" \
  && pass "kill-pane: its orphan (pid $o_b) stopped, the other pane's kept" \
  || fail "kill-pane: orphans ${o_b:-none} (should go), ${o_a:-none} (should stay)"
t kill-window -t "$w"
gone "${o_a:-0}" && pass "kill-window: the orphan of the pane it closed (pid $o_a) stopped" \
  || fail "kill-window left its orphan (pid ${o_a:-none}) running"

# Several at once: a reap per window and one for the session, side by side.
t new-session -d -s cl5 sleep 100000
read -r a _ < <(orphan_in cl5)
read -r b _ < <(orphan_in cl5)
read -r c _ < <(orphan_in cl5)
t kill-session -t =cl5
gone "${a:-0}" && gone "${b:-0}" && gone "${c:-0}" && pass "a three-window session closed: all three orphans stopped" \
  || fail "a three-window session closed: left: $(ps -o pid=,args= -p "${a:-0},${b:-0},${c:-0}" | tr '\n' ';')"

# A session started as another closes is not taken for a leftover: tmux moves a
# pane into its scope only a moment after starting it. The new session comes
# 0 to 0.45 s after the close, across the hook's own run.
for i in $(seq 0 15); do
  t new-session -d -s "clr$i" sleep 100000
  t kill-session -t "=clr$i"
  sleep "$(printf '0.%02d' $((i * 3)))"
  t new-session -d -s "cln$i" sleep 100000
done
sleep 3
born=$(t list-sessions -F '#S' | grep -c '^cln')
[ "$born" -eq 16 ] && pass "16 sessions started as another closed all survive its reap" \
  || fail "of 16 sessions started as another closed, $born survive its reap"
for i in $(seq 0 15); do t kill-session -t "=cln$i" 2>/dev/null; done

# A tmux server started from a pane stays in that pane's scope, with sessions
# of its own to lose: the pane closing must not end it.
nest() { tmux -L nested "$@"; }
pane=$(t new-window -d -P -F '#{pane_id}' -t =cl2: \
  "sh -c 'tmux -L nested -f /dev/null new-session -d -s n sleep 100000; exec sleep 100000'")
for _ in $(seq 30); do
  nested=$(nest display -p '#{pid}' 2>/dev/null) && break
  sleep 0.1
done
t kill-pane -t "$pane"
sleep 1.5
[ -n "$nested" ] && kill -0 "$nested" 2>/dev/null && nest has-session -t =n 2>/dev/null \
  && pass "a tmux server started from a closed pane keeps running (pid $nested)" \
  || fail "the nested server ${nested:-none} went with the pane that started it"
nest kill-server

# A server that runs but cannot be reached is not a server gone: its scopes are
# still its own, and the reap stops none of them.
shell_pid=$(t display -p -t =manager:0 '#{pane_pid}')
mv "$SOCKPATH" "$SOCKPATH.away"
reap "$SOCKPATH"
rc=$?
mv "$SOCKPATH.away" "$SOCKPATH"
[ "$rc" -eq 0 ] && kill -0 "$shell_pid" 2>/dev/null && alive "${o2:-}" \
  && pass "a reap with the server unreachable stops nothing" \
  || fail "a reap with the server unreachable: exit $rc, shell $shell_pid, orphan $o2"

# Another socket's leftovers are not this one's, with their server up or gone.
# That server has no hooks, so its orphan stays until the reap of its own socket.
tmux_other() { tmux -L other -f /dev/null "$@"; }
tmux_other new-session -d -s keep sleep 100000
read -r o_other pane < <(orphan_in keep "" tmux_other)
tmux_other kill-pane -t "$pane"
reap "$SOCKPATH"
sleep 0.5
alive "${o_other:-}" && pass "a reap leaves another live server's leftover" \
  || fail "the reap of one socket took another live server's job"
other_pid=$(tmux_other display -p '#{pid}')
tmux_other kill-server
gone "$other_pid" || fail "server $other_pid outlived kill-server by 5 s"
reap "$SOCKPATH"
sleep 0.5
alive "${o_other:-}" && pass "and that server's once it is gone" \
  || fail "the reap of one socket took a dead server's job"
reap "${SOCKPATH%/*}/other"
gone "${o_other:-0}" && pass "the reap of its own socket stops it" \
  || fail "the reap of its own socket left job ${o_other:-none}"

# A hand-started server, without the variable a login gives: the hook finds
# systemd all the same. A login's bus address stays: tmux reaches systemd through
# it to give panes scopes, and a CI runner, which has none of its own, would leave
# this server's panes with no scope for the hook to stop.
hand() {
  env -u XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
    HOME="$H" tmux -L hand "$@"
}
hand new-session -d -s h1 sleep 100000
hand new-session -d -s h2 sleep 100000
read -r o_h _ < <(orphan_in h1 "" hand)
hand kill-session -t =h1
gone "${o_h:-0}" && pass "a hand-started server's closed session: its orphan (pid $o_h) stopped" \
  || fail "a hand-started server's closed session left job ${o_h:-none}"
hand kill-server

# The last session: the server exits with it (exit-empty) with nothing left to
# run the hook, so the next server's start sweeps. This ends the manager too.
read -r o_last _ < <(orphan_in cl2)
t kill-session -t =manager
t kill-session -t =cl2
sleep 0.5
start_unit
if [ -n "$o2" ] && gone "$o2" && gone "${o_last:-0}"; then pass "the next start sweeps what the last session left"; else
  fail "pids $o2, ${o_last:-none} survived the server and the next start"
fi
claude_of manager >/dev/null && pass "and comes up" || fail "no claude after the sweep's start"

# --- the record -------------------------------------------------------------

reaped=$(cat "$H"/.dotfiles/.logs/*_tmux_hooks/events.log 2>/dev/null | grep -c 'reaped tmux-spawn-')
[ "$reaped" -ge 2 ] && pass "each reap is logged with what it stopped ($reaped lines)" \
  || fail "reaps logged: $reaped, expected at least 2 (tmux hooks log)"
# A FAILED line is a reap that picked a live pane's scope, or one another took.
failed_reaps=$(grep -h 'FAILED to stop' "$H"/.dotfiles/.logs/*_tmux_hooks/events.log 2>/dev/null)
[ -z "$failed_reaps" ] && pass "no reap failed during the run" || fail "reaps failed: $failed_reaps"
ls "$H"/.dotfiles/.logs/*_claude_manager_start/events.log >/dev/null 2>&1 \
  && pass "the start keeps its event log" || fail "no claude_manager_start event log"

if [ "$failures" -eq 0 ]; then log "all checks passed"; else log "$failures check(s) failed"; fi
exit "$((failures > 0))"

#!/usr/bin/env bash
# check.sh covers: home/.config/tmux/client-clock.sh home/.config/tmux/tmux.conf home/.config/fish/conf.d/client_tz.fish scripts/lib/event_log.sh
#
# tmux_client_clock_test.sh -- the tmux bar's clock in each client's own zone
# (home/.config/tmux/client-clock.sh, the LC_CLIENT_TZ that
# home/.config/fish/conf.d/client_tz.fish exports on a Mac), in a throwaway
# tmux server and HOME. Needs tmux, python3 and fish; about 10 s.
#
#   client-clock.sh, run as tmux runs it, on a process holding:
#     LC_CLIENT_TZ=Asia/Yerevan    -> Linux: "<date> HH:MM +04", Yerevan's
#                                     macOS: the server's time (no environ)
#     no LC_CLIENT_TZ              -> the server's time and zone
#     LC_CLIENT_TZ=Mars/Olympus    -> Linux: exit 1, "no .../Mars/Olympus",
#     LC_CLIENT_TZ=../../etc/passwd   "not a zone name"; each logged
#     a pid that is gone           -> Linux: exit 1, "cannot read ..."
#     no pid                       -> exit 1, the usage, logged
#
#   a server from the whole tmux.conf, session w, three clients on it:
#     Asia/Yerevan, Pacific/Kiritimati, none
#                                  -> Linux: each bar shows its own zone's
#                                     time (+04, +14, the server's)
#                                     macOS: all three the server's
#
#   fish on a Mac                  -> LC_CLIENT_TZ is /etc/localtime's zone
#   fish on Linux, LC_CLIENT_TZ    -> passed on as it came, not replaced
#   from ssh
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux python3 fish; do
  command -v "$cmd" >/dev/null || {
    echo "tmux_client_clock_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/clocktest.XXXXXX)
SOCK="$SOCKDIR/clock"
TMUX_BIN=$(command -v tmux)
OS=$(uname)
FORMAT='%d %b %H:%M %Z'

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
pids=()
cleanup() {
  local p
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  t kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# The throwaway HOME holds the repo at ~/.dotfiles, as tmux.conf's #()
# lines name it, and takes the event log lines (~/.dotfiles/.logs).
mkdir -p "$H/.dotfiles"
ln -s "$REPO/home" "$H/.dotfiles/home"
ln -s "$REPO/scripts" "$H/.dotfiles/scripts"
CLOCK="$H/.dotfiles/home/.config/tmux/client-clock.sh"
clock_log() { cat "$H"/.dotfiles/.logs/*_client_clock/events.log 2>/dev/null; }

# in_zone <zone|-> <strftime>: the time now in that zone; "-" the server's
# (no TZ: what a tmux server started with env -i below would print)
in_zone() {
  if [ "$1" = - ]; then env -u TZ date "+$2"; else TZ=$1 date "+$2"; fi
}
# expect <zone|->: what client-clock.sh should print for a client in it on
# this OS: macOS cannot read the client's zone, so the server's
expect_zone() { if [ "$OS" = Linux ]; then echo "$1"; else echo -; fi; }

# --- client-clock.sh on its own ----------------------------------------------

# clock_for <LC_CLIENT_TZ|->: the script's output and exit code for a sleeper
# holding that zone (or none), run as tmux runs a job: the server's
# environment, here none but HOME and PATH.
clock_for() {
  local holder
  if [ "$1" = - ]; then
    env -u LC_CLIENT_TZ sleep 30 &
  else
    LC_CLIENT_TZ=$1 sleep 30 &
  fi
  holder=$!
  out=$(env -i HOME="$H" PATH=/usr/bin:/bin "$CLOCK" "$holder" 2>&1)
  rc=$?
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
}

# The zone's time is read before and after, so a minute that turns between
# is no failure.
for zone in Asia/Yerevan Pacific/Kiritimati -; do
  before=$(in_zone "$(expect_zone "$zone")" "$FORMAT")
  clock_for "$zone"
  after=$(in_zone "$(expect_zone "$zone")" "$FORMAT")
  if [ "$rc" = 0 ] && { [ "$out" = "$before" ] || [ "$out" = "$after" ]; }; then
    shown=$(expect_zone "$zone")
    pass "LC_CLIENT_TZ ${zone/#-/unset} on $OS -> '$out', ${shown/#-/server} time"
  else
    fail "LC_CLIENT_TZ=$zone on $OS: rc=$rc '$out', wanted '$after'"
  fi
done

if [ "$OS" = Linux ]; then
  clock_for Mars/Olympus
  [ "$rc" = 1 ] && grep -qF "LC_CLIENT_TZ='Mars/Olympus': no /usr/share/zoneinfo/Mars/Olympus" <<<"$out" \
    && clock_log | grep -qF "LC_CLIENT_TZ='Mars/Olympus'" \
    && pass "an unknown zone is refused and logged: '$out'" \
    || fail "unknown zone: rc=$rc '$out'; log: $(clock_log | tail -1)"

  clock_for ../../etc/passwd
  [ "$rc" = 1 ] && grep -qF "is not a zone name" <<<"$out" \
    && pass "a path for a zone is refused: '$out'" || fail "path zone: rc=$rc '$out'"

  sleep 0 &
  gone=$!
  wait "$gone"
  out=$(env -i HOME="$H" PATH=/usr/bin:/bin "$CLOCK" "$gone" 2>&1)
  rc=$?
  [ "$rc" = 1 ] && grep -qF "cannot read /proc/$gone/environ" <<<"$out" \
    && pass "a client gone says so: '$out'" || fail "gone client: rc=$rc '$out'"
fi

out=$(env -i HOME="$H" PATH=/usr/bin:/bin "$CLOCK" 2>&1)
rc=$?
[ "$rc" = 1 ] && grep -qF "usage: client-clock.sh <client pid>" <<<"$out" \
  && clock_log | grep -qF "usage: client-clock.sh" \
  && pass "no pid: the usage, logged: '$out'" || fail "no pid: rc=$rc '$out'; log: $(clock_log | tail -1)"

# --- the bar, end to end -----------------------------------------------------

# A server of its own from the whole tmux.conf, a stub tmux-mem-cpu-load for
# status-stats.sh (whose error would otherwise crowd the clock out of the
# bar), and three clients in ptys on one session, each in its own zone.
t() { env -i HOME="$H" PATH="$(dirname "$TMUX_BIN"):/usr/bin:/bin" TERM=xterm-256color "$TMUX_BIN" -S "$SOCK" "$@"; }
mkdir -p "$H/.nix-profile/bin"
cat >"$H/.nix-profile/bin/tmux-mem-cpu-load" <<'STUB'
#!/bin/sh
printf '73.98%%   7.8%%\n'
STUB
chmod +x "$H/.nix-profile/bin/tmux-mem-cpu-load"
t -f "$H/.dotfiles/home/.config/tmux/tmux.conf" new-session -d -s w -x 120 -y 30 'sleep 300' 2>"$WORK/out" \
  || fail "the server would not start from tmux.conf: $(cat "$WORK/out")"

# attach <name> <zone|->: a client of w in a pty, with LC_CLIENT_TZ as an
# ssh login would hand it; what tmux draws to it goes to $WORK/<name>.screen
attach() {
  python3 - "$TMUX_BIN" "$SOCK" "$H" "$2" "$WORK/$1.screen" <<'PYEOF' &
import os, pty, sys
tmux, sock, home, zone, screen = sys.argv[1:]
env = {"HOME": home, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color"}
if zone != "-":
    env["LC_CLIENT_TZ"] = zone
out = open(screen, "wb", buffering=0)
pid, fd = pty.fork()
if pid == 0:
    os.execve(tmux, [tmux, "-S", sock, "attach", "-t", "=w"], env)
while True:
    try:
        data = os.read(fd, 65536)
    except OSError:
        break
    if not data:
        break
    out.write(data)
PYEOF
  pids+=($!)
}
attach yerevan Asia/Yerevan
attach kiritimati Pacific/Kiritimati
attach server -
for _ in $(seq 50); do
  [ "$(t list-clients -t =w | wc -l)" -ge 3 ] && break
  sleep 0.1
done

# Each client's bar ends with a clock in its zone. The #() job's first draw
# is empty (the job still running), so wait for the time to show. The time
# by pattern, then checked against the zone's minute before and after.
for client in yerevan:Asia/Yerevan kiritimati:Pacific/Kiritimati server:-; do
  name=${client%%:*}
  sent=${client#*:}
  zone=$(expect_zone "$sent")
  before=$(in_zone "$zone" '%H:%M')
  want="\| $(in_zone "$zone" '%d %b') [0-9]{2}:[0-9]{2} $(in_zone "$zone" '%Z' | sed 's/+/\\+/')"
  for _ in $(seq 100); do
    grep -aqE "$want" "$WORK/$name.screen" && break
    sleep 0.1
  done
  drawn=$(grep -aoE "$want" "$WORK/$name.screen" | tail -1)
  after=$(in_zone "$zone" '%H:%M')
  hm=$(grep -oE '[0-9]{2}:[0-9]{2}' <<<"$drawn")
  if [ -n "$drawn" ] && { [ "$hm" = "$before" ] || [ "$hm" = "$after" ]; }; then
    pass "client $name (LC_CLIENT_TZ ${sent/#-/unset}, on $OS: ${zone/#-/server} time) draws '${drawn#| }'"
  else
    fail "client $name never drew '$want' at $after; screen: $(tr -c '[:print:]' ' ' <"$WORK/$name.screen" | grep -oE 'mem [0-9.]+% \| [^ ]+ [^ ]+ [^ ]+ [^ ]+' | tail -2)"
  fi
done

# --- fish's side --------------------------------------------------------------

# The conf.d file alone (the rest of the config wants fisher and more), in
# a fish of no config; its stderr kept, so a complaint of its own shows.
fish_tz() {
  env -i HOME="$H" PATH="$(dirname "$(command -v fish)"):/usr/bin:/bin" "$@" \
    fish --no-config -c 'source $argv[1]; echo "$LC_CLIENT_TZ"' \
    "$REPO/home/.config/fish/conf.d/client_tz.fish" 2>&1
}
if [ "$OS" = Darwin ]; then
  want=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
  got=$(fish_tz)
  [ -n "$want" ] && [ "$got" = "$want" ] && pass "fish on a Mac exports LC_CLIENT_TZ=$got" \
    || fail "fish on a Mac: LC_CLIENT_TZ='$got', /etc/localtime says '$want'"
  got=$(fish_tz LC_CLIENT_TZ=Asia/Yerevan)
  [ "$got" = "$want" ] && pass "fish on a Mac puts its own zone over an inherited one" \
    || fail "fish on a Mac with LC_CLIENT_TZ=Asia/Yerevan inherited: '$got', wanted '$want'"
else
  got=$(fish_tz LC_CLIENT_TZ=Asia/Yerevan)
  [ "$got" = Asia/Yerevan ] && pass "fish on $OS passes on the zone ssh brought" \
    || fail "fish on $OS replaced LC_CLIENT_TZ=Asia/Yerevan with '$got'"
  got=$(fish_tz)
  [ -z "$got" ] && pass "fish on $OS sets no LC_CLIENT_TZ of its own" \
    || fail "fish on $OS set LC_CLIENT_TZ='$got'"
fi

[ "$failures" -eq 0 ] && log "all passed" || log "$failures failed"
[ "$failures" -eq 0 ]

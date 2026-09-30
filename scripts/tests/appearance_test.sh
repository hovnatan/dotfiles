#!/usr/bin/env bash
#
# appearance_test.sh -- end-to-end checks for scripts/appearance.sh, which
# points Claude Code's theme and zathura's colours at light or dark. Runs the
# script for real in a throwaway HOME; zathura and the session bus are stood
# in for, so no window opens and the machine's own links stay as they are.
# Needs python3 and a tmux with theme hooks (3.6 or later); about 5 s.
#
#   throwaway HOME
#     .claude/themes/gruvbox-{light,dark}.json    copies of the repo's
#     .config/zathura/gruvbox-{light,dark}        copies of the repo's
#     .cache/bus                                  a socket nobody answers on
#     bin/zathura                                 only has to exist
#     bin/dbus-send                               records its arguments;
#                                                 answers ListNames with two
#                                                 zathura windows, anything
#                                                 else with "boolean true"
#
#   links        light, dark, light again; a second run changes nothing
#   arguments    an unknown one, and none on Linux, fail
#   in the way   a file where the link goes fails, and is left alone
#   no zathura   links only
#   windows      each window gets each `set` line of the theme, in order
#   refused      a window answering false fails the run
#   theme file   a line that is not a `set` fails the run
#   tmux         the two hooks of home/.tmux.conf, in a throwaway server: a
#                client in a pty reports its theme as a terminal does
#                (CSI ? 997 ; 2 n = light, ; 1 n = dark), the links follow
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for cmd in python3 tmux; do
  command -v "$cmd" >/dev/null || { echo "appearance_test.sh: $cmd not on PATH" >&2; exit 1; }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$REPO/scripts/appearance.sh"
WORK=$(mktemp -d)
H="$WORK/home"
# Unix socket paths are capped near 104 bytes, so not under $WORK.
SOCKDIR=$(mktemp -d /tmp/apptest.XXXXXX)
TMUX_BIN=$(command -v tmux)

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() { log "FAIL $*"; failures=$((failures + 1)); }

cleanup() {
  [ -n "${listener:-}" ] && kill "$listener" 2>/dev/null
  "$TMUX_BIN" -S "$SOCKDIR/tmux" kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# --- the throwaway HOME -------------------------------------------------------

mkdir -p "$H/.claude/themes" "$H/.config/zathura" "$H/bin"
cp "$REPO"/home/.claude/themes/gruvbox-{light,dark}.json "$H/.claude/themes/"
cp "$REPO"/home/.config/zathura/gruvbox-{light,dark} "$H/.config/zathura/"

cat > "$H/bin/dbus-send" <<'STUB'
#!/bin/sh
# Stand-in for dbus-send: one line per call in $CALLS, the destination and
# the last argument.
for arg in "$@"; do
  case "$arg" in --dest=*) dest=${arg#--dest=} ;; esac
  last=$arg
done
echo "$dest | $last" >> "$CALLS"
case "$last" in
  *ListNames)
    printf '   array [\n      string "org.freedesktop.DBus"\n      string "org.pwmt.zathura.PID-11"\n      string ":1.7"\n      string "org.pwmt.zathura.PID-22"\n   ]\n'
    ;;
  *) echo "   boolean ${ANSWER:-true}" ;;
esac
STUB
chmod +x "$H/bin/dbus-send"

# Run the script in the throwaway HOME. PATH is the system's plus bin/, so
# the machine's own zathura and dbus-send are out of reach; $1 says whether
# bin/ is on it at all.
run() {
  local with_zathura=$1
  shift
  local path=/usr/bin:/bin
  [ "$with_zathura" = zathura ] && path="$H/bin:$path"
  env -i HOME="$H" PATH="$path" XDG_RUNTIME_DIR="$SOCKDIR" CALLS="$WORK/calls" ANSWER="${ANSWER:-true}" \
    "$SCRIPT" "$@" > "$WORK/out" 2>&1
}
points_at() { [ "$(readlink "$1")" = "$2" ]; }
both_point_at() {
  points_at "$H/.claude/themes/gruvbox.json" "gruvbox-$1.json" && points_at "$H/.config/zathura/theme" "gruvbox-$1"
}

# --- links --------------------------------------------------------------------

for mode in light dark light; do
  if run no-zathura "$mode" && both_point_at "$mode"; then
    pass "links: $mode"
  else
    fail "links: $mode (exit $?, $(cat "$WORK/out"))"
  fi
done
if run no-zathura light && both_point_at light && [ "$(grep -c ' already$' "$WORK/out")" -eq 2 ]; then
  pass "links: a second run finds both in place"
else
  fail "links: a second run: $(cat "$WORK/out")"
fi
if grep -q 'no zathura on this machine' "$WORK/out"; then
  pass "no zathura: links only"
else
  fail "no zathura: $(cat "$WORK/out")"
fi

# --- arguments ----------------------------------------------------------------

if run no-zathura blue; then
  fail "arguments: 'blue' was taken"
elif grep -q "unknown appearance 'blue'" "$WORK/out" && both_point_at light; then
  pass "arguments: 'blue' refused, links untouched"
else
  fail "arguments: 'blue': $(cat "$WORK/out")"
fi
if [ "$(uname)" = "Linux" ]; then
  if run no-zathura; then
    fail "arguments: none was taken on Linux"
  elif grep -q 'no appearance given' "$WORK/out"; then
    pass "arguments: none refused on Linux"
  else
    fail "arguments: none on Linux: $(cat "$WORK/out")"
  fi
fi

# --- a file in the way ----------------------------------------------------------

rm "$H/.config/zathura/theme"
echo "mine" > "$H/.config/zathura/theme"
if run no-zathura dark; then
  fail "in the way: the file was replaced"
elif grep -q 'is a file, not a link' "$WORK/out" && [ "$(cat "$H/.config/zathura/theme")" = "mine" ]; then
  pass "in the way: refused, file left alone"
else
  fail "in the way: $(cat "$WORK/out")"
fi
rm "$H/.config/zathura/theme"

# --- the windows ----------------------------------------------------------------

touch "$H/bin/zathura" && chmod +x "$H/bin/zathura"
if run zathura dark; then
  fail "windows: ran without a bus"
elif grep -q 'no session bus at' "$WORK/out"; then
  pass "windows: no bus is an error"
else
  fail "windows: no bus: $(cat "$WORK/out")"
fi

python3 -c 'import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); time.sleep(60)' "$SOCKDIR/bus" &
listener=$!
for _ in $(seq 50); do [ -S "$SOCKDIR/bus" ] && break; sleep 0.1; done

: > "$WORK/calls"
{
  echo "org.freedesktop.DBus | org.freedesktop.DBus.ListNames"
  for pid in 11 22; do
    sed -n 's/^set /string:set /p' "$H/.config/zathura/gruvbox-dark" | sed "s/^/org.pwmt.zathura.PID-$pid | /"
  done
} > "$WORK/expected"
if run zathura dark && diff "$WORK/expected" "$WORK/calls" > "$WORK/diff"; then
  pass "windows: both got the $(grep -c '^set ' "$H/.config/zathura/gruvbox-dark") set lines of the dark theme"
else
  fail "windows: $(cat "$WORK/out" "$WORK/diff")"
fi

if ANSWER=false run zathura light; then
  fail "refused: a window answering false passed"
elif grep -q 'org.pwmt.zathura.PID-11 refused' "$WORK/out"; then
  pass "refused: a window answering false fails the run"
else
  fail "refused: $(cat "$WORK/out")"
fi

echo 'map r recolor' >> "$H/.config/zathura/gruvbox-dark"
if run zathura dark; then
  fail "theme file: a map line passed"
elif grep -q 'not a set line: map r recolor' "$WORK/out"; then
  pass "theme file: a line that is not a set fails the run"
else
  fail "theme file: $(cat "$WORK/out")"
fi

# --- tmux ---------------------------------------------------------------------

# The hooks as home/.tmux.conf has them, and nothing else of it. They name
# ~/.dotfiles/scripts/appearance.sh, so the throwaway HOME gets that path.
# The server's PATH is the system's: the machine's zathura stays out of reach.
sed -i.bak '$d' "$H/.config/zathura/gruvbox-dark" # the map line from above
rm "$H/bin/zathura"
mkdir -p "$H/.dotfiles/scripts"
ln -s "$SCRIPT" "$H/.dotfiles/scripts/appearance.sh"
grep -E '^set-hook -g client-(dark|light)-theme ' "$REPO/home/.tmux.conf" > "$WORK/hooks.conf"
if [ "$(wc -l < "$WORK/hooks.conf")" -eq 2 ]; then
  pass "tmux: home/.tmux.conf has the two hooks"
else
  fail "tmux: hooks in home/.tmux.conf: $(cat "$WORK/hooks.conf")"
fi
t() { env -i HOME="$H" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$SOCKDIR" TERM=xterm-256color "$TMUX_BIN" -S "$SOCKDIR/tmux" "$@"; }
t -f /dev/null new-session -d -s t
if t source-file "$WORK/hooks.conf" 2> "$WORK/out"; then
  pass "tmux: $("$TMUX_BIN" -V) takes the hooks"
else
  fail "tmux: $("$TMUX_BIN" -V) refused the hooks: $(cat "$WORK/out")"
fi

# A client in a pty, reporting light, then dark, then light; after each it
# waits for both links and prints "<mode> ok" or what it found instead.
python3 - "$TMUX_BIN" "$SOCKDIR/tmux" "$H" > "$WORK/client.out" 2>&1 <<'PYEOF'
import os, pty, select, sys, time
tmux, sock, home = sys.argv[1:]
links = {home + "/.claude/themes/gruvbox.json": "gruvbox-%s.json", home + "/.config/zathura/theme": "gruvbox-%s"}
pid, fd = pty.fork()
if pid == 0:
    env = {"HOME": home, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color"}
    os.execve(tmux, [tmux, "-S", sock, "attach", "-t", "=t"], env)

def drain(seconds):
    end = time.time() + seconds
    while time.time() < end:
        if select.select([fd], [], [], 0.1)[0]:
            try: os.read(fd, 65536)
            except OSError: return

def found():
    return {l: (os.readlink(l) if os.path.islink(l) else None) for l in links}

drain(1)
for mode, report in (("light", b"\x1b[?997;2n"), ("dark", b"\x1b[?997;1n"), ("light", b"\x1b[?997;2n")):
    os.write(fd, report)
    end = time.time() + 5
    while time.time() < end and any(found()[l] != links[l] % mode for l in links):
        drain(0.1)
    wrong = {l: t for l, t in found().items() if t != links[l] % mode}
    print(mode, "ok" if not wrong else "not followed: %s" % wrong, flush=True)
PYEOF
if [ "$(tr '\n' ' ' < "$WORK/client.out")" = "light ok dark ok light ok " ]; then
  pass "tmux: the links follow the client's theme, light, dark, light"
else
  fail "tmux: $(cat "$WORK/client.out")"
fi

log "$failures failure(s)"
[ "$failures" -eq 0 ]

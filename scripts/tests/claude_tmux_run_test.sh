#!/usr/bin/env bash
#
# claude_tmux_run_test.sh -- end-to-end checks for scripts/claude_tmux_run.sh
# and the claude-tmux.service ExecStop line, on a throwaway tmux socket with a
# throwaway HOME and a stub claude. Never touches the live "claude" socket,
# the real service, or any real conversation. Linux only: it needs a user
# systemd manager (transient units, scopes) and tmux. Takes about 5 s.
#
#   throwaway HOME: .profile       the installer's hook -> home/.profile.shared
#                   .dotfiles  ->  this repo
#                   .local/bin/claude   stub: `agents --json` -> [], otherwise
#                                       an idle process whose comm is "claude"
#
#   transient unit (like claude-tmux.service, KillMode=process)
#     $SHELL -lc claude_tmux_run.sh --> server in tmux-server-<socket>.scope
#                                         +- "claude" pane (the manager)
#   claude_tmux_run.sh spawn ctb ------->  +- "ctb" pane
#
# Checks, each printed as PASS/FAIL with a timestamp:
#   - the manager comes up from the service-like unit; spawn succeeds
#   - panes start as `<passwd shell> -lc`, run claude, have no pipe-pane log,
#     and carry the profile environment (EDITOR, MAKEFLAGS, WORDLIST, ...)
#     with the throwaway ~/.local/bin first on PATH
#   - the server sits in its own scope and panes are PartOf it, so stopping
#     the unit leaves every session alive (tmux >= 3.7 PartOf regression)
#   - the unit file's real ExecStop line, run with systemd's own PATH, kills
#     the manager and only the manager (d2ab7417 regression)
#   - a HOME with no transcripts yet does not crash the transcript reader
#
# Usage: scripts/tests/claude_tmux_run_test.sh   (exit 0 = all passed)
# On failure the work dir (stub, profile, unit output) is kept and printed.

set -uo pipefail

[ "$(uname)" = Linux ] || { echo "claude_tmux_run_test.sh: Linux only (needs systemd --user)" >&2; exit 1; }
for cmd in tmux systemd-run systemctl getent python3; do
  command -v "$cmd" >/dev/null || { echo "claude_tmux_run_test.sh: $cmd not on PATH" >&2; exit 1; }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SOCK="cttest-$$"                   # socket, transient unit and scope all carry it
UNIT="$SOCK"
WORK=$(mktemp -d)
H="$WORK/home"
LOGIN_SHELL=$(getent passwd "$(id -un)" | cut -d: -f7)

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() { log "FAIL $*"; failures=$((failures + 1)); }
t() { tmux -L "$SOCK" "$@"; }

# Tear down everything this run created, whatever state it stopped in.
cleanup() {
  systemctl --user stop "$UNIT" 2>/dev/null
  t kill-server 2>/dev/null
  systemctl --user reset-failed "$UNIT" 2>/dev/null
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# --- throwaway HOME ---------------------------------------------------------

# The stub must win over the real claude on every PATH a login shell builds,
# or the "manager" below would resume a real conversation. Its idle process
# is a copy of sleep named claude: wait_alive checks the pane's comm.
mkdir -p "$H/.local/bin" "$H/.claude/projects" "$WORK/idle"
ln -s "$REPO" "$H/.dotfiles"
# The real Nix profile, so login shells here pick the same tmux the service
# does: without it the server runs the distro's tmux (3.4 on Ubuntu 24.04),
# which never sets PartOf, and the scope checks below pass without testing.
[ -e "$HOME/.nix-profile" ] && ln -s "$(readlink -f "$HOME/.nix-profile")" "$H/.nix-profile"
cp "$(command -v sleep)" "$WORK/idle/claude"
cat > "$H/.local/bin/claude" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = agents ] && { echo '[]'; exit 0; }
exec "$WORK/idle/claude" 100000
EOF
chmod +x "$H/.local/bin/claude"

# ~/.profile exactly as setup_user_symlinks.sh appends it.
cat > "$H/.profile" <<'EOF'
if [ -f "$HOME/.dotfiles/home/.profile.shared" ]; then
  . "$HOME/.dotfiles/home/.profile.shared"
fi
EOF

resolved=$(env -i HOME="$H" USER="$USER" PATH=/usr/bin:/bin "$LOGIN_SHELL" -lc 'command -v claude')
if [ "$resolved" != "$H/.local/bin/claude" ]; then
  log "ABORT: a login shell in the throwaway HOME resolves claude to '$resolved', not the stub"
  failures=1
  exit 1
fi
log "work dir $WORK, socket $SOCK, login shell $LOGIN_SHELL"

# --- empty-transcripts regression -------------------------------------------

out=$(HOME="$H" PATH="$H/.local/bin:$PATH" CLAUDE_TMUX_SOCKET="$SOCK" \
  "$REPO/scripts/claude_tmux_run.sh" history nobody 2>&1)
if grep -q Traceback <<<"$out"; then fail "history on a HOME without transcripts: traceback"; else pass "history on a HOME without transcripts"; fi

# --- manager from a service-like unit, then a spawn -------------------------

systemd-run --user --quiet --unit="$UNIT" -p KillMode=process \
  -E HOME="$H" -E SHELL="$LOGIN_SHELL" -E CLAUDE_TMUX_SOCKET="$SOCK" -E CLAUDE_TMUX_ALIVE_SECONDS=2 \
  /bin/sh -c 'exec "$SHELL" -lc "$HOME/.dotfiles/scripts/claude_tmux_run.sh"'
for _ in $(seq 40); do t has-session -t claude 2>/dev/null && break; sleep 0.25; done
if t has-session -t claude 2>/dev/null; then pass "manager session up from the unit"; else fail "manager session never appeared"; exit 1; fi

if HOME="$H" PATH="$H/.local/bin:$PATH" CLAUDE_TMUX_SOCKET="$SOCK" CLAUDE_TMUX_ALIVE_SECONDS=2 \
     "$REPO/scripts/claude_tmux_run.sh" spawn ctb /tmp >"$WORK/spawn.out" 2>&1; then
  pass "spawn ctb: $(cat "$WORK/spawn.out")"
else
  fail "spawn ctb: $(cat "$WORK/spawn.out")"
fi

# --- each pane: launcher, process, logging, environment ---------------------

for s in claude ctb; do
  pid=$(t list-panes -t "=$s:" -F '#{pane_pid}' 2>/dev/null)
  [ -n "$pid" ] || { fail "$s: no pane"; continue; }
  start=$(t display -p -t "=$s:" '#{pane_start_command}')
  case "$start" in
    "$LOGIN_SHELL -lc "*) pass "$s: starts as '$LOGIN_SHELL -lc'" ;;
    *) fail "$s: start command is '$start'" ;;
  esac
  [ "$(ps -o comm= -p "$pid")" = claude ] && pass "$s: pane process is claude" || fail "$s: pane process is $(ps -o comm= -p "$pid")"
  [ "$(t display -p -t "=$s:" '#{pane_pipe}')" = 0 ] && pass "$s: no pipe-pane log" || fail "$s: pane is piped"

  env_of() { tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p"; }
  missing=""
  for v in EDITOR MAKEFLAGS WORDLIST COLORTERM LANG; do [ -n "$(env_of "$v")" ] || missing="$missing $v"; done
  [ "$(env_of CLAUDE_CODE_DISABLE_AGENT_VIEW)" = 1 ] || missing="$missing CLAUDE_CODE_DISABLE_AGENT_VIEW"
  [ -z "$missing" ] && pass "$s: profile environment present" || fail "$s: missing from environment:$missing"
  first=$(env_of PATH | cut -d: -f1)
  [ "$first" = "$H/.local/bin" ] && pass "$s: ~/.local/bin first on PATH" || fail "$s: PATH starts with $first"
done

# --- server scope and PartOf: stopping the unit keeps sessions --------------

server_pid=$(t display -p '#{pid}')
server_version=$(t display -p '#{version}')
log "server runs tmux $server_version ($(readlink "/proc/$server_pid/exe"))"
server_unit=$(sed 's|.*/||' "/proc/$server_pid/cgroup")
[ "$server_unit" = "tmux-server-$SOCK.scope" ] && pass "server in $server_unit" || fail "server in $server_unit"
# tmux >= 3.7 ties each pane's scope to the unit that started its server:
# that must be the server's own scope. Older tmux sets no PartOf at all.
if printf '3.7\n%s\n' "${server_version%%[a-z]*}" | sort -V -C; then want="tmux-server-$SOCK.scope"; else want=""; fi
for s in claude ctb; do
  pid=$(t list-panes -t "=$s:" -F '#{pane_pid}')
  partof=$(systemctl --user show "$(sed 's|.*/||' "/proc/$pid/cgroup")" -p PartOf --value)
  [ "$partof" = "$want" ] && pass "$s: pane PartOf '${partof:-nothing}' (tmux $server_version)" \
    || fail "$s: pane PartOf '${partof:-nothing}', expected '${want:-nothing}' (tmux $server_version)"
done

systemctl --user stop "$UNIT"
sleep 1
alive=$(t list-sessions -F '#S' 2>/dev/null | sort | tr '\n' ' ')
[ "$alive" = "claude ctb " ] && pass "unit stop left both sessions alive" || fail "after unit stop, sessions: '${alive}'"

# --- the unit file's ExecStop, under systemd's own environment --------------

# The real line, with systemd's specifiers filled in: %h is HOME, and a set
# ${MAINPID} marks a real stop request (not a restart cycle).
stop_line=$(sed -n 's/^ExecStop=//p' "$REPO/home/.config/systemd/user/claude-tmux.service")
stop_script=$(sed -n "s/^\/bin\/sh -c '\(.*\)'\$/\1/p" <<<"$stop_line")
stop_script=${stop_script//%h/$H}
stop_script=${stop_script//\$\{MAINPID\}/1}
[ -n "$stop_script" ] || { fail "could not parse ExecStop from the unit file: $stop_line"; exit 1; }
systemd-run --user --quiet --wait --pipe \
  -E HOME="$H" -E SHELL="$LOGIN_SHELL" -E CLAUDE_TMUX_SOCKET="$SOCK" \
  /bin/sh -c "$stop_script" >"$WORK/execstop.out" 2>&1
rc=$?
alive=$(t list-sessions -F '#S' 2>/dev/null | sort | tr '\n' ' ')
if [ "$rc" -eq 0 ] && [ "$alive" = "ctb " ]; then
  pass "ExecStop killed only the manager"
else
  fail "ExecStop rc=$rc, sessions left: '${alive}'; output: $(tr '\n' ' ' < "$WORK/execstop.out")"
fi

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

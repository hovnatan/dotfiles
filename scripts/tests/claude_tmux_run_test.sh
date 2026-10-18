#!/usr/bin/env bash
# check.sh covers: scripts/claude_tmux_run.sh scripts/lib/* home/.config/systemd/user/claude-tmux.service home/.profile.shared
# check.sh runs-on: Linux
#
# claude_tmux_run_test.sh -- end-to-end checks for scripts/claude_tmux_run.sh
# and the claude-tmux.service Exec lines, on a throwaway tmux socket with a
# throwaway HOME and a stub claude. Never touches the live "claude" socket,
# the real service, or any real conversation. Linux only: it needs a user
# systemd manager (transient units, scopes) and tmux. Takes about 10 s.
#
#   throwaway HOME: .profile       the installer's hook -> home/.profile.shared
#                   .dotfiles  ->  this repo
#                   .local/bin/claude   stub: `agents --json` -> [], otherwise
#                                       an idle process whose comm is "claude"
#
#   transient unit (like claude-tmux.service, KillMode=process)
#     the unit file's ExecStart -----> server in tmux-server-<socket>.scope
#                                         +- "claude" pane (the manager)
#   claude_tmux_run.sh new ctb /tmp ---->  +- "ctb" pane
#
# Checks, each printed as PASS/FAIL with a timestamp:
#   - the manager comes up from the unit file's real ExecStart line (serve);
#     new succeeds
#   - panes start as `<passwd shell> -lc`, run claude, have no pipe-pane log,
#     and carry the profile environment (EDITOR, MAKEFLAGS, WORDLIST, ...)
#     with the throwaway ~/.local/bin first on PATH
#   - the server sits in its own scope and panes are PartOf it, so stopping
#     the unit leaves every session alive (tmux >= 3.7 PartOf regression),
#     and nothing of the watcher's behind in the unit's cgroup (its sleep
#     outlived it, a "left-over process" on every restart)
#   - the unit file's real ExecStop line, run with systemd's own PATH, kills
#     the manager and only the manager (860dbdcc regression)
#   - a HOME with no transcripts yet does not crash the transcript reader
#   - with the real home/.tmux.conf loaded (the claude server reads it), a
#     session whose claude exited does not stay (remain-on-exit on would
#     keep it, and the watcher would never restart the manager)
#   - a second window the user opened in a session does not make status
#     read it as dead (claude is searched across the session's panes), and
#     status run from inside a session reports every other session's own
#     pane (a bare =name target matched a window of the current session)
#   - when `claude agents --json` fails, load, status and conversations
#     stop with an error instead of acting on "nothing open" (a resume
#     would double-open the conversation)
#   - `stop <name>[/<task>]` kills exactly that session, never one whose
#     name merely starts with <name> (tmux's bare targets prefix-match),
#     nor a labeled <name>/<task> when given the bare <name>; a miss lists
#     the labeled ones; a hand-set label outside NAME_RE is still stoppable;
#     bare `stop` (ExecStop) finds a labeled manager, and fails rather than
#     succeeds when tmux itself fails
#   - load <name>/<task> resumes by id in its own <name>/<task> session
#     beside a live <name> (one live session per full name, label included)
#   - new under a used bare name starts a fresh conversation in the given
#     directory (no --resume); new refuses a
#     live session of that name and a label some conversation carries;
#     load refuses a name with no conversation and any directory; no
#     subcommand and an unknown one (the retired spawn) fail at once
#     instead of reaching the watch loop, which would block forever
#   - load <name>/<task> refuses a label two conversations carry, but not
#     one conversation resumed into two transcripts; load --id resumes the
#     conversation holding that id at its newest transcript, and refuses an
#     id nothing holds
#
# Usage: scripts/tests/claude_tmux_run_test.sh   (exit 0 = all passed)
# On failure the work dir (stub, profile, unit output) is kept and printed.

set -uo pipefail

[ "$(uname)" = Linux ] || {
  echo "claude_tmux_run_test.sh: Linux only (needs systemd --user)" >&2
  exit 1
}
for cmd in tmux systemd-run systemctl getent python3; do
  command -v "$cmd" >/dev/null || {
    echo "claude_tmux_run_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SOCK="cttest-$$" # socket, transient unit and scope all carry it
UNIT="$SOCK"
WORK=$(mktemp -d)
H="$WORK/home"
LOGIN_SHELL=$(getent passwd "$(id -un)" | cut -d: -f7)

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
t() { tmux -L "$SOCK" "$@"; }
# Every session on the test socket, sorted, space-separated: "ctb ctb2 ".
sessions() { t list-sessions -F '#S' 2>/dev/null | LC_ALL=C sort | tr '\n' ' '; }
start_of() { t display -p -t "=$1:" '#{pane_start_command}' 2>/dev/null; }
# transcript <title> <id> [<first prompt uuid> <day>]: a conversation in
# /tmp, titled for this host -- one load would resume -- talked in on
# 2026-01-<day> (default 01). Transcripts sharing a uuid are one
# conversation resumed into a second file; without one, each stands alone.
transcript() {
  mkdir -p "$H/.claude/projects/-tmp"
  printf '%s\n' "{\"type\":\"user\",\"cwd\":\"/tmp\",\"uuid\":\"${3:-$2}\",\"timestamp\":\"2026-01-${4:-01}T00:00:00.000Z\",\"message\":{\"content\":\"hi\"}}" \
    "{\"type\":\"custom-title\",\"customTitle\":\"$(hostname)-$1\",\"sessionId\":\"$2\"}" \
    >"$H/.claude/projects/-tmp/$2.jsonl"
}
# unit_line <key>: the unit file's <key>= line as the script /bin/sh -c
# runs, with systemd's %h filled in (HOME) -- the real line, so a test of
# it is a test of what systemd runs.
unit_line() {
  local line
  line=$(sed -n "s/^$1=//p" "$REPO/home/.config/systemd/user/claude-tmux.service")
  line=$(sed -n "s/^\/bin\/sh -c '\(.*\)'\$/\1/p" <<<"$line")
  [ -n "$line" ] || {
    fail "could not parse $1 from the unit file"
    exit 1
  }
  echo "${line//%h/$H}"
}

# Tear down everything this run created, whatever state it stopped in.
cleanup() {
  systemctl --user stop "$UNIT" 2>/dev/null
  t kill-server 2>/dev/null
  # tmux leaves its socket file behind when the server exits, so each run
  # would add a dead /tmp/tmux-<uid>/cttest-<pid>. Same path rule as tmux's.
  rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"
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
# With $WORK/agents_fail present, `agents --json` fails the way a broken
# Claude Code update or daemon would.
cat >"$H/.local/bin/claude" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = agents ]; then
  [ -e "$WORK/agents_fail" ] && { echo 'agents: daemon did not start' >&2; exit 1; }
  echo '[]'; exit 0
fi
exec "$WORK/idle/claude" 100000
EOF
chmod +x "$H/.local/bin/claude"

# ~/.profile exactly as setup_user_symlinks.sh appends it.
cat >"$H/.profile" <<'EOF'
if [ -f "$HOME/.dotfiles/home/.profile.shared" ]; then
  . "$HOME/.dotfiles/home/.profile.shared"
fi
EOF

# The real tmux config, which the claude socket's server reads like any
# other: its options decide whether a dead pane keeps its session.
ln -s "$REPO/home/.tmux.conf" "$H/.tmux.conf"

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

# --- manager from a service-like unit, then a new ---------------------------

start_script=$(unit_line ExecStart) || exit 1
systemd-run --user --quiet --unit="$UNIT" -p KillMode=process \
  -E HOME="$H" -E SHELL="$LOGIN_SHELL" -E CLAUDE_TMUX_SOCKET="$SOCK" -E CLAUDE_TMUX_ALIVE_SECONDS=2 \
  /bin/sh -c "$start_script"
for _ in $(seq 40); do
  t has-session -t claude 2>/dev/null && break
  sleep 0.25
done
if t has-session -t claude 2>/dev/null; then pass "manager session up from the unit"; else
  fail "manager session never appeared"
  exit 1
fi

if HOME="$H" PATH="$H/.local/bin:$PATH" CLAUDE_TMUX_SOCKET="$SOCK" CLAUDE_TMUX_ALIVE_SECONDS=2 \
  "$REPO/scripts/claude_tmux_run.sh" new ctb /tmp >"$WORK/new.out" 2>&1; then
  pass "new ctb: $(cat "$WORK/new.out")"
else
  fail "new ctb: $(cat "$WORK/new.out")"
fi

on_exit=$(t show -gv remain-on-exit 2>/dev/null)
[ "$on_exit" = off ] && pass "remain-on-exit off with home/.tmux.conf loaded" \
  || fail "remain-on-exit is '$on_exit' with home/.tmux.conf loaded"

# --- a second window in a session: status still finds its claude ------------

run() { HOME="$H" PATH="$H/.local/bin:$PATH" CLAUDE_TMUX_SOCKET="$SOCK" CLAUDE_TMUX_ALIVE_SECONDS=2 "$REPO/scripts/claude_tmux_run.sh" "$@"; }
t new-window -t "=ctb:" sleep 100000 # current from now on, as prefix c makes it
st=$(run status 2>&1)
if grep -q '^== ctb \[claude pid' <<<"$st"; then pass "status finds claude in ctb behind a second window"; else
  fail "status with a second window in ctb: $(grep '^== ctb' <<<"$st")"
fi
t kill-window -t "=ctb:{end}" # the window just opened (highest index)

# Run from inside ctb, as the manager or a user in a pane does: tmux then
# resolves a bare "=claude" window target to ctb's own window (named
# "claude" after its process) before trying the session "claude".
t rename-window -t =ctb:0 claude # what automatic-rename calls it, made certain
inside="$(t display -p -t =ctb: '#{socket_path},#{pid},#{session_id}')"
st=$(TMUX="${inside/\$/}" TMUX_PANE="$(t display -p -t =ctb: '#{pane_id}')" run status 2>&1)
want=$(t list-panes -t =claude: -F '#{pane_pid}')
if grep -q "^== claude \[claude pid $want\]" <<<"$st"; then pass "status from inside ctb reports the manager's own pane"; else
  fail "status from inside ctb, manager pane $want: $(grep '^== claude' <<<"$st")"
fi

# --- claude agents --json failing: no command acts on "nothing open" --------

# A conversation load would resume: its transcript, titled for this host.
transcript ctr 0000-ctr
touch "$WORK/agents_fail"
for cmd in "load ctr" status conversations; do
  # shellcheck disable=SC2086 # cmd is two words on purpose
  out=$(run $cmd 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] && grep -q 'agents --json' <<<"$out"; then pass "$cmd stops when agents --json fails"; else
    fail "$cmd with agents --json failing: rc=$rc, $(head -c 200 <<<"$out")"
  fi
done
t has-session -t =ctr 2>/dev/null && fail "load ctr resumed the conversation anyway"
t kill-session -t =ctr 2>/dev/null
rm -f "$WORK/agents_fail" "$H/.claude/projects/-tmp/0000-ctr.jsonl"

# --- each pane: launcher, process, logging, environment ---------------------

for s in claude ctb; do
  pid=$(t list-panes -t "=$s:" -F '#{pane_pid}' 2>/dev/null)
  [ -n "$pid" ] || {
    fail "$s: no pane"
    continue
  }
  start=$(start_of "$s")
  case "$start" in
    "$LOGIN_SHELL -lc "*) pass "$s: starts as '$LOGIN_SHELL -lc'" ;;
    *) fail "$s: start command is '$start'" ;;
  esac
  [ "$(ps -o comm= -p "$pid")" = claude ] && pass "$s: pane process is claude" || fail "$s: pane process is $(ps -o comm= -p "$pid")"
  [ "$(t display -p -t "=$s:" '#{pane_pipe}')" = 0 ] && pass "$s: no pipe-pane log" || fail "$s: pane is piped"

  env_of() { tr '\0' '\n' <"/proc/$pid/environ" | sed -n "s/^$1=//p"; }
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

cgroup=$(systemctl --user show "$UNIT" -p ControlGroup --value)
systemctl --user stop "$UNIT"
# KillMode=process signals only the watcher, so a child it leaves running
# (the loop's sleep) stays in the unit's cgroup -- systemd then logs "left-over
# process" on every restart. Read at once: such a child ends within 5 s.
left=$(cat "/sys/fs/cgroup$cgroup/cgroup.procs" 2>/dev/null | tr '\n' ' ')
[ -z "$left" ] && pass "unit stop left nothing in the unit's cgroup" \
  || fail "unit stop left in $cgroup: $left($(ps -o comm= -p "${left%% *}"))"
sleep 1
alive=$(sessions)
[ "$alive" = "claude ctb " ] && pass "unit stop left both sessions alive" || fail "after unit stop, sessions: '${alive}'"

# --- the unit file's ExecStop, under systemd's own environment --------------

# A set ${MAINPID} marks a real stop request (not a restart cycle).
stop_script=$(unit_line ExecStop) || exit 1
stop_script=${stop_script//\$\{MAINPID\}/1}
# Under a label, as /label leaves it: ExecStop must still find it.
t rename-session -t =claude claude/x
systemd-run --user --quiet --wait --pipe \
  -E HOME="$H" -E SHELL="$LOGIN_SHELL" -E CLAUDE_TMUX_SOCKET="$SOCK" \
  /bin/sh -c "$stop_script" >"$WORK/execstop.out" 2>&1
rc=$?
alive=$(sessions)
if [ "$rc" -eq 0 ] && [ "$alive" = "ctb " ]; then
  pass "ExecStop killed only the manager (labeled claude/x)"
else
  fail "ExecStop rc=$rc, sessions left: '${alive}'; output: $(tr '\n' ' ' <"$WORK/execstop.out")"
fi

# --- stop <name>: exact sessions only ---------------------------------------

t new-session -d -s ctb2 sleep 100000
out=$(run stop ct 2>&1)
rc=$?
alive=$(sessions)
[ "$rc" -ne 0 ] && [ "$alive" = "ctb ctb2 " ] && pass "stop ct: refused ($out), ctb and ctb2 untouched" \
  || fail "stop ct: rc=$rc ($out), sessions left: '$alive'"
out=$(run stop ctb 2>&1)
alive=$(sessions)
[ "$alive" = "ctb2 " ] && pass "stop ctb: killed ctb only ($out)" || fail "stop ctb: sessions left: '$alive' ($out)"

# A labeled session is a different conversation: the bare name never reaches
# it, only its full <name>/<task> does (`stop api` killed api/docs).
t new-session -d -s ctb/task sleep 100000
out=$(run stop ctb 2>&1)
rc=$?
alive=$(sessions)
[ "$rc" -ne 0 ] && [ "$alive" = "ctb/task ctb2 " ] && grep -q 'under that name: ctb/task ' <<<"$out" && pass "stop ctb: refused ($out), ctb/task untouched" \
  || fail "stop ctb with only ctb/task live: rc=$rc ($out), sessions left: '$alive'"
out=$(run stop ctb/task 2>&1)
rc=$?
alive=$(sessions)
[ "$rc" -eq 0 ] && [ "$alive" = "ctb2 " ] && pass "stop ctb/task: killed ctb/task only ($out)" \
  || fail "stop ctb/task: sessions left: '$alive' ($out)"

# A label set by hand (/rename, the /resume picker) may hold characters
# outside NAME_RE; its session must still be stoppable by its full name.
t new-session -d -s 'ctb/issue#42' sleep 100000
out=$(run stop 'ctb/issue#42' 2>&1)
rc=$?
alive=$(sessions)
[ "$rc" -eq 0 ] && [ "$alive" = "ctb2 " ] && pass "stop ctb/issue#42: killed it ($out)" \
  || fail "stop ctb/issue#42: rc=$rc ($out), sessions left: '$alive'"

# A name with a leading "-" is a name, not grep options.
out=$(run stop -x 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -q '^no session -x on' <<<"$out" && pass "stop -x: refused as a name ($out)" \
  || fail "stop -x: rc=$rc ($out)"

# tmux failing for any reason but "no server" is not "nothing to stop":
# ExecStop would report success with the manager still up.
mkdir -p "$WORK/badtmux"
printf '#!/bin/sh\necho "protocol version mismatch (client 8, server 9)" >&2\nexit 1\n' >"$WORK/badtmux/tmux"
chmod +x "$WORK/badtmux/tmux"
out=$(HOME="$H" PATH="$WORK/badtmux:$H/.local/bin:$PATH" CLAUDE_TMUX_SOCKET="$SOCK" \
  "$REPO/scripts/claude_tmux_run.sh" stop 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -q 'protocol version mismatch' <<<"$out" && pass "stop with tmux failing: refused ($out)" \
  || fail "stop with tmux failing: rc=$rc ($out)"

# One live session per FULL name: a labeled conversation starts in its own
# session beside a live one under the same bare name, named after its title,
# resuming the conversation by id.
transcript ctb2/a 0000-ctb2a
out=$(run load ctb2/a 2>&1)
rc=$?
alive=$(sessions)
start=$(start_of ctb2/a)
[ "$rc" -eq 0 ] && [ "$alive" = "ctb2 ctb2/a " ] && [[ "$start" == *"--resume 0000-ctb2a "* ]] \
  && pass "load ctb2/a beside ctb2: resumed 0000-ctb2a in its own session ($out)" \
  || fail "load ctb2/a beside ctb2: rc=$rc ($out), sessions: '$alive', start '$start'"
t kill-session -t =ctb2/a
rm -f "$H/.claude/projects/-tmp/0000-ctb2a.jsonl"

# --- new and load: a fresh conversation vs an existing one -----------------

# A used bare name: new must start FRESH, in the directory given -- the
# reason it exists, since a bare spawn reattached to the newest conversation
# under the name and no form of it could start an unlabeled one.
transcript ctn 0000-ctn
mkdir -p "$WORK/fresh"
out=$(run new ctn "$WORK/fresh" 2>&1)
rc=$?
start=$(start_of ctn)
where=$(t display -p -t =ctn: '#{pane_current_path}' 2>/dev/null)
if [ "$rc" -eq 0 ] && [[ "$start" != *--resume* ]] && [[ "$start" == *"-n $(hostname)-ctn "* ]] && [ "$where" = "$WORK/fresh" ]; then
  pass "new ctn beside an existing ctn conversation: fresh, in its directory ($out)"
else
  fail "new ctn: rc=$rc ($out), start '$start', cwd '$where'"
fi

# The session of that name is live: new refuses rather than start a second
# one; load accepts it as already up (any conversation, for a bare name).
out=$(run new ctn /tmp 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -q 'already running' <<<"$out" && [ "$(sessions)" = "ctb2 ctn " ] \
  && pass "new ctn with ctn live: refused ($out)" || fail "new ctn with ctn live: rc=$rc ($out), sessions '$(sessions)'"
out=$(run load ctn 2>&1)
rc=$?
[ "$rc" -eq 0 ] && grep -q 'already running' <<<"$out" && pass "load ctn with ctn live: already running ($out)" \
  || fail "load ctn with ctn live: rc=$rc ($out)"

t kill-session -t =ctn

# A label pins one conversation: new refuses to start a second carrier.
transcript ctn/x 0000-ctnx
out=$(run new ctn/x /tmp 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -q 'already carries that label' <<<"$out" && ! t has-session -t =ctn/x 2>/dev/null \
  && pass "new ctn/x with the label taken: refused ($out)" || fail "new ctn/x with the label taken: rc=$rc ($out)"

# Arguments each command cannot use are errors, not silently dropped.
for args in "load ctnone" "load ctn /tmp" "new ctn" "new ctn /tmp /var" "new ctnone $WORK/missing"; do
  # shellcheck disable=SC2086 # args is several words on purpose
  out=$(run $args 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] && [ "$(sessions)" = "ctb2 " ] && pass "$args: refused ($(head -c 120 <<<"$out"))" \
    || fail "$args: rc=$rc ($out), sessions '$(sessions)'"
done

# No subcommand, and any unknown one (the retired spawn included), fails at
# once: only serve may reach the watch loop, which blocks while the manager
# lives. A watchdog kills a regression after 10 s rather than timeout(1),
# which macOS lacks (check.sh lints it).
for args in "" "spawn ctn /tmp"; do
  # shellcheck disable=SC2086 # args is several words, or none, on purpose
  run $args >"$WORK/bare.out" 2>&1 &
  bg=$!
  (
    sleep 10
    kill "$bg" 2>/dev/null
  ) &
  dog=$!
  wait "$bg"
  rc=$?
  kill "$dog" 2>/dev/null
  wait "$dog" 2>/dev/null
  out=$(cat "$WORK/bare.out")
  [ "$rc" -eq 1 ] && grep -q '^usage:' <<<"$out" && pass "'$args': refused at once ($(head -c 120 <<<"$out"))" \
    || fail "'$args': rc=$rc (143: killed by the watchdog, i.e. in the watch loop) ($out)"
done
grep -q 'daemon-reload' "$WORK/bare.out" && fail "spawn: the bare-call daemon-reload hint shows for a subcommand" \
  || pass "spawn: no daemon-reload hint (that is for a bare call)"

# Two conversations carrying one label: load cannot tell which is meant and
# says so, naming both. One conversation resumed into a second transcript
# (same first prompt) is still one: new sees the label as taken, not
# ambiguous.
transcript ctn/x 0000-ctnx2
out=$(run load ctn/x 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -q '0000-ctnx[,)]' <<<"$out" && grep -q '0000-ctnx2[,)]' <<<"$out" && ! t has-session -t =ctn/x 2>/dev/null \
  && pass "load ctn/x carried twice: refused ($out)" || fail "load ctn/x carried twice: rc=$rc ($out)"
transcript ctn/y 0000-ctny1 u-ctny 01
transcript ctn/y 0000-ctny2 u-ctny 02
out=$(run new ctn/y /tmp 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -q '(0000-ctny2) already carries that label' <<<"$out" \
  && pass "new ctn/y over one conversation in two transcripts: label taken, not ambiguous ($out)" \
  || fail "new ctn/y over one conversation in two transcripts: rc=$rc ($out)"

# load --id: an older transcript's id reaches its conversation, resumed at
# the newest one; an id nothing holds is refused.
out=$(run load --id 0000-ctny1 2>&1)
rc=$?
start=$(start_of ctn/y)
[ "$rc" -eq 0 ] && [[ "$start" == *"--resume 0000-ctny2 "* ]] && pass "load --id 0000-ctny1: resumed 0000-ctny2 ($out)" \
  || fail "load --id 0000-ctny1: rc=$rc ($out), start '$start'"
t kill-session -t =ctn/y 2>/dev/null
out=$(run load --id 0000-nothing 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -q 'no titled conversation has id 0000-nothing' <<<"$out" && pass "load --id 0000-nothing: refused ($out)" \
  || fail "load --id 0000-nothing: rc=$rc ($out)"
rm -f "$H/.claude/projects/-tmp/"0000-ctn*.jsonl

# --- a session ends when its process exits -----------------------------------

kill "$(t list-panes -t =ctb2: -F '#{pane_pid}')"
sleep 1
t has-session -t =ctb2 2>/dev/null && fail "ctb2's process exited but the session remains (dead pane kept)" \
  || pass "ctb2's process exited and its session went with it"

log "$([ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed")"
exit $((failures > 0))

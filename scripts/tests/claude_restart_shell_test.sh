#!/usr/bin/env bash
# check.sh covers: scripts/claude_tmux_run.sh home/.config/tmux/restart-claude.sh home/.tmux.conf scripts/lib/*
#
# claude_restart_shell_test.sh -- end-to-end checks for restarting a claude
# typed at a shell's prompt (`claude_tmux_run.sh restart --pane`, and
# prefix C-r from home/.tmux.conf), on any tmux server: what a Mac's default
# server runs. A throwaway tmux server, HOME and stub claude; never touches
# a real server, session or conversation. Needs tmux, python3, bash, fish
# and zsh (the quoting rules the resume is typed in); about a minute.
#
#   throwaway HOME: .dotfiles/{home,scripts}   this checkout, so the binding
#                                              and the restart run it, and
#                                              its event logs land here
#                   .local/bin/claude   stub: `agents --json` lists every
#                                       live stub; otherwise it records its
#                                       argv and conversation, then idles
#                                       as a process whose comm is "claude"
#                   .claude/projects/   conversation 0000-ctsh in $D, its
#                                       last prompt in the mode under test,
#                                       untitled (as one started by hand
#                                       is) or under a custom title
#
#   server (home/.tmux.conf)
#     sh-bash   bash -i in $D   claude typed at its prompt
#     sh-fish   fish -i in $D   likewise, renamed to one that needs quoting
#     sh-zsh    zsh -i in $D    likewise
#     misc      bash -i elsewhere, a bare prompt, claude as a pane's process,
#               a shell in a directory since removed
#
# Checks, each printed as PASS/FAIL with a timestamp:
#   - restart --check lists nothing for an idle claude; restart TERMs it
#     and types `claude --resume <id> [-n <name>] <mode>` at the same
#     shell's prompt (same shell pid): the mode the transcript's LAST prompt
#     recorded (bypassPermissions as --dangerously-skip-permissions,
#     another as --permission-mode); no -n for a conversation with no custom
#     title, whose auto-generated name would replace its AI title; for one
#     with a custom title, the name agents --json shows, in the current
#     "<host>/" form, quoted for bash, zsh and fish (a ', a \ and a $ in it);
#     and the verdict names the pane
#   - the mode survives a last prompt over 1 MiB back; title and mode survive
#     a newer untitled transcript folded onto the conversation
#   - a resume continuing under a new id is a success, and logged
#   - refused, claude untouched: a busy one (unless --force), a shell in
#     another directory than the conversation's, the two both removed, a
#     bare prompt (no claude in the foreground), a claude that is the pane's
#     own process but not launched by claude_tmux_run.sh
#   - in-view: "pane" on any server but the claude socket; there "session",
#     but "pane" for a claude the session did not launch
#   - a claude ignoring TERM gets KILL after CLAUDE_TMUX_EXIT_SECONDS and is
#     resumed all the same
#   - prefix C-r, typed into an attached client on a server that is not
#     the claude socket: a popup naming the pane's session:window, y
#     restarts the claude in view, the verdict on the message line, from
#     copy mode too; C-r on a bare prompt says there is no claude there, on
#     a pane since closed that it is gone
#
# Usage: scripts/tests/claude_restart_shell_test.sh   (exit 0 = all passed)
# On failure the work dir is kept and printed.

set -uo pipefail

for cmd in tmux python3 bash fish zsh; do
  command -v "$cmd" >/dev/null || {
    echo "claude_restart_shell_test.sh: $cmd not on PATH" >&2
    exit 1
  }
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(cd "$(mktemp -d)" && pwd -P) # real path: macOS's TMPDIR is behind /var -> /private/var
H="$WORK/home"
D="$WORK/proj"
# Unix socket paths are capped near 104 bytes, so not under $WORK; and not
# named "claude", so restart-claude.sh treats it as any other server.
SOCKDIR=$(mktemp -d /tmp/ctsh.XXXXXX)
SOCK="$SOCKDIR/s"
TMUX_BIN=$(command -v tmux)

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}

# Everything the server, its panes and the scripts run reach by this PATH:
# the stub first, then the tools' own directories (bash 5 for `env bash`:
# macOS's /bin/bash is 3.2), then the system's (ps, lsof).
P="$H/.local/bin"
for cmd in tmux bash python3 fish zsh; do P+=":$(dirname "$(command -v "$cmd")")"; done
P+=":/usr/bin:/bin:/usr/sbin:/sbin"
t() { env -i HOME="$H" PATH="$P" USER="$USER" TERM=xterm-256color "$TMUX_BIN" -S "$SOCK" "$@"; }
# run <restart args...>: claude_tmux_run.sh restart as C-r runs it, with
# $EXIT, when set, as its CLAUDE_TMUX_EXIT_SECONDS.
run() {
  local extra=()
  [ -z "${EXIT:-}" ] || extra=(CLAUDE_TMUX_EXIT_SECONDS="$EXIT")
  env -i HOME="$H" PATH="$P" USER="$USER" CLAUDE_TMUX_ALIVE_SECONDS=1 "${extra[@]}" \
    "$H/.dotfiles/scripts/claude_tmux_run.sh" restart "$@"
}

# in_view <claude socket name> <pane>: what C-r picks there, with that name
# as the claude socket's.
in_view() {
  env -i HOME="$H" PATH="$P" USER="$USER" CLAUDE_TMUX_SOCKET="$1" \
    "$H/.dotfiles/scripts/claude_tmux_run.sh" in-view "$SOCK" "$2"
}

cleanup() {
  [ -n "${client_job:-}" ] && kill "$client_job" 2>/dev/null
  t kill-server 2>/dev/null
  rm -rf "$SOCKDIR"
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# --- throwaway HOME, stub, transcript ---------------------------------------

mkdir -p "$H/.dotfiles" "$H/.local/bin" "$H/.claude/projects/-proj" "$D" "$WORK/elsewhere" \
  "$WORK/idle" "$WORK/agents.d"
ln -s "$REPO/home" "$H/.dotfiles/home"
ln -s "$REPO/scripts" "$H/.dotfiles/scripts"

# The stub's idle process is a copy of bash named claude, waiting on a FIFO
# nobody writes (not sleep: Ubuntu 26.04's is a multi-call binary that
# refuses another name). Same pid as the stub, which execs it, so the record
# it wrote names it. $WORK/name holds the name a fresh one reports (what
# claude agents shows for a conversation never renamed), $WORK/status its
# state (idle unless "busy"); with $WORK/ignore_term it ignores TERM, which
# the exec keeps. With $WORK/new_id a resume reports that id, as one
# continuing in a new transcript does.
cp "$(command -v bash)" "$WORK/idle/claude"
mkfifo "$WORK/idle/never"
echo auto-name >"$WORK/name"
cat >"$WORK/agents.py" <<'EOF'
import json, os, sys
work = sys.argv[1]
status = open(os.path.join(work, "status")).read().strip() if os.path.exists(os.path.join(work, "status")) else "idle"
agents = []
for f in sorted(os.listdir(os.path.join(work, "agents.d"))):
    try:
        os.kill(int(f), 0)
    except ProcessLookupError:
        continue
    sid, name = open(os.path.join(work, "agents.d", f)).read().split("\n")[:2]
    agents.append({"pid": int(f), "sessionId": sid, "name": name, "status": status})
print(json.dumps(agents))
EOF
cat >"$H/.local/bin/claude" <<EOF
#!/bin/bash
[ "\${1:-}" = agents ] && exec python3 "$WORK/agents.py" "$WORK"
printf '%s\n' "\$@" >"$WORK/argv.\$\$"
id=0000-fresh name=\$(cat "$WORK/name")
while [ \$# -gt 0 ]; do
  case \$1 in
    --resume) id=\$2 && shift ;;
    -n) name=\$2 && shift ;;
  esac
  shift
done
[ ! -e "$WORK/new_id" ] || id=\$(cat "$WORK/new_id")
printf '%s\n%s\n' "\$id" "\$name" >"$WORK/agents.d/\$\$"
[ -e "$WORK/ignore_term" ] && trap '' TERM
exec "$WORK/idle/claude" -c "read -r -t 100000 <>'$WORK/idle/never'"
EOF
chmod +x "$H/.local/bin/claude"

# transcript <mode> [<custom title>]: conversation 0000-ctsh in $D, its
# first prompt in "default" and its last in <mode> -- a Shift-Tab between
# them -- with an AI title always, and that custom title if given.
transcript() {
  printf '%s\n' \
    "{\"type\":\"user\",\"cwd\":\"$D\",\"uuid\":\"u1\",\"timestamp\":\"2026-01-01T00:00:00.000Z\",\"permissionMode\":\"default\",\"message\":{\"content\":\"hi\"}}" \
    "{\"type\":\"assistant\",\"cwd\":\"$D\",\"uuid\":\"a1\",\"timestamp\":\"2026-01-01T00:00:05.000Z\",\"message\":{\"content\":\"hello\"}}" \
    "{\"type\":\"user\",\"cwd\":\"$D\",\"uuid\":\"u2\",\"timestamp\":\"2026-01-01T00:01:00.000Z\",\"permissionMode\":\"$1\",\"message\":{\"content\":\"again\"}}" \
    "{\"type\":\"ai-title\",\"aiTitle\":\"greeting\",\"sessionId\":\"0000-ctsh\"}" \
    >"$H/.claude/projects/-proj/0000-ctsh.jsonl"
  [ -z "${2:-}" ] || printf '%s\n' "{\"type\":\"custom-title\",\"customTitle\":\"${2//\\/\\\\}\",\"sessionId\":\"0000-ctsh\"}" \
    >>"$H/.claude/projects/-proj/0000-ctsh.jsonl"
}

# --- the server and its shells ----------------------------------------------

# Each command as separate words, which tmux execs as they are: one string
# would go through a shell first, which would then be the pane's process.
t -f "$H/.dotfiles/home/.tmux.conf" new-session -d -s sh-bash -x 160 -y 40 -c "$D" bash --norc --noprofile -i
t new-session -d -s sh-fish -x 160 -y 40 -c "$D" fish --no-config -i
t new-session -d -s sh-zsh -x 160 -y 40 -c "$D" zsh -f -i
t new-session -d -s misc -x 160 -y 40 -c "$WORK/elsewhere" bash --norc --noprofile -i
bpane=$(t display -p -t =sh-bash: '#{pane_id}')
fpane=$(t display -p -t =sh-fish: '#{pane_id}')
zpane=$(t display -p -t =sh-zsh: '#{pane_id}')
mpane=$(t display -p -t =misc: '#{pane_id}')

shell_of() { t display -p -t "$1" '#{pane_pid}'; }
# fg_of <pane>: the process group holding the pane's terminal.
fg_of() { ps -o tpgid= -p "$(shell_of "$1")" | tr -d ' '; }
# claude_in <pane>: the stub in the pane's foreground, or nothing.
claude_in() {
  local f c
  f=$(fg_of "$1")
  c=$(ps -o comm= -p "$f" 2>/dev/null)
  [ "${c##*/}" = claude ] && [ -e "$WORK/agents.d/$f" ] && echo "$f"
}
# prompt_up <pane>: wait until the shell has drawn something (its prompt).
prompt_up() {
  for _ in $(seq 100); do
    [ -n "$(t capture-pane -p -t "$1" | tr -d ' \n')" ] && return 0
    sleep 0.1
  done
  return 1
}
# hand_start <pane> <command>: type it at the shell's prompt, as the user
# does; prints the claude's pid once it runs in the foreground.
hand_start() {
  local c
  prompt_up "$1" || fail "no prompt in $1: $(t capture-pane -p -t "$1")"
  t send-keys -t "$1" -l -- "$2"
  t send-keys -t "$1" Enter
  for _ in $(seq 100); do
    c=$(claude_in "$1") && [ -n "$c" ] && echo "$c" && return 0
    sleep 0.1
  done
  fail "typed '$2' in $1, but no claude came up in its foreground: $(t capture-pane -p -t "$1" | tail -5)"
  return 1
}
# check_restarted <what> <pane> <shell pid> <old claude> <want argv, one per line>:
# pass when the same shell runs a new claude in the foreground, started
# with exactly that argv, on conversation 0000-ctsh.
check_restarted() {
  local new argv rec
  new=$(claude_in "$2")
  argv=$(cat "$WORK/argv.$new" 2>/dev/null)
  rec=$(head -1 "$WORK/agents.d/$new" 2>/dev/null)
  if [ "$rc" -eq 0 ] && [ "$(shell_of "$2")" = "$3" ] && [ -n "$new" ] && [ "$new" != "$4" ] \
    && ! kill -0 "$4" 2>/dev/null && [ "$argv" = "$5" ] && [ "$rec" = 0000-ctsh ]; then
    pass "$1: shell $3 kept, claude $4 -> $new, argv $(paste -sd ' ' - <<<"$argv") ($(tail -n 1 <<<"$out"))"
  else
    fail "$1: rc=$rc, shell $3 -> $(shell_of "$2"), claude $4 -> '$new', argv '$argv', conversation '$rec'; output: $out"
  fi
}

# --- bash: the restart, and its refusals --------------------------------------

transcript bypassPermissions
old=$(hand_start "$bpane" 'claude --resume 0000-ctsh') || exit 1
sh_pid=$(shell_of "$bpane")

out=$(run --check --pane "$SOCK" "$bpane" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && pass "restart --check on an idle claude: nothing listed" \
  || fail "restart --check on an idle claude: rc=$rc, '$out'"

echo busy >"$WORK/status"
out=$(run --pane "$SOCK" "$bpane" 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -qF "pane $bpane (sh-bash) is not idle (busy: a turn)" <<<"$out" && [ "$(claude_in "$bpane")" = "$old" ] \
  && pass "restart of a busy claude: refused, untouched ($out)" || fail "restart of a busy claude: rc=$rc ($out)"
out=$(run --force --pane "$SOCK" "$bpane" 2>&1)
rc=$?
check_restarted "restart --force of a busy claude" "$bpane" "$sh_pid" "$old" \
  "$(printf '%s\n' --resume 0000-ctsh --dangerously-skip-permissions)"
rm "$WORK/status"

# The claude this restart starts ignores TERM, for the KILL check next.
old=$(claude_in "$bpane")
touch "$WORK/ignore_term"
out=$(run --pane "$SOCK" "$bpane" 2>&1)
rc=$?
check_restarted "restart in bash, last prompt in bypassPermissions" "$bpane" "$sh_pid" "$old" \
  "$(printf '%s\n' --resume 0000-ctsh --dangerously-skip-permissions)"
grep -qF "pane $bpane (sh-bash): restarted conversation 0000-ctsh (auto-name) in $D (--dangerously-skip-permissions)" <<<"$out" \
  && pass "the verdict names the pane, conversation and mode" || fail "the verdict: $out"

old=$(claude_in "$bpane")
rm "$WORK/ignore_term"
out=$(EXIT=1 run --pane "$SOCK" "$bpane" 2>&1)
rc=$?
check_restarted "restart of a claude ignoring TERM" "$bpane" "$sh_pid" "$old" \
  "$(printf '%s\n' --resume 0000-ctsh --dangerously-skip-permissions)"
grep -qF 'still up 1 s after TERM; sending KILL' "$H"/.dotfiles/.logs/*_claude_tmux_restart/events.log \
  && pass "the KILL is logged" || fail "no KILL in the restart logs"

# One claude per conversation from here on: the restart refuses one open
# in two processes, so bash's goes before the next is started on it.
kill "$(claude_in "$bpane")"

# A bare prompt: nothing in the foreground but the shell.
prompt_up "$mpane"
[ "$(in_view other "$mpane")" = pane ] && [ "$(in_view s "$mpane")" = session ] \
  && pass "in-view at a bare prompt: the pane elsewhere, the session on the claude socket" \
  || fail "in-view at a bare prompt: '$(in_view other "$mpane")', '$(in_view s "$mpane")'"
out=$(run --pane "$SOCK" "$mpane" 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -qF "no claude in the foreground of pane $mpane (misc)" <<<"$out" \
  && pass "restart at a bare prompt: refused ($out)" || fail "restart at a bare prompt: rc=$rc ($out)"

# The shell in another directory than the conversation's.
old=$(hand_start "$mpane" 'claude --resume 0000-ctsh') || exit 1
out=$(run --pane "$SOCK" "$mpane" 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -qF "but conversation 0000-ctsh belongs to $D" <<<"$out" && [ "$(claude_in "$mpane")" = "$old" ] \
  && pass "restart from a shell in another directory: refused, untouched" || fail "restart from another directory: rc=$rc ($out)"
[ "$(in_view s "$mpane")" = pane ] && pass "in-view on a claude typed at a prompt on the claude socket: the pane" \
  || fail "in-view on a typed claude: '$(in_view s "$mpane")'"
kill "$old"

# Shell and conversation in one directory, since removed: both resolve to
# nothing, which is no match. The resume would only fail there.
mkdir "$WORK/gone"
gpane=$(t new-window -d -P -F '#{pane_id}' -t =misc: -c "$WORK/gone" bash --norc --noprofile -i)
D="$WORK/gone" transcript default
old=$(hand_start "$gpane" 'claude --resume 0000-ctsh') || exit 1
rm -rf "$WORK/gone"
out=$(run --pane "$SOCK" "$gpane" 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -qF "but conversation 0000-ctsh belongs to $WORK/gone" <<<"$out" && [ "$(claude_in "$gpane")" = "$old" ] \
  && pass "restart in a removed directory: refused, untouched" || fail "restart in a removed directory: rc=$rc ($out)"
kill "$old"
t kill-pane -t "$gpane"

# claude as a pane's own process, not launched by claude_tmux_run.sh: no
# shell to type at, no launch to repeat.
cpane=$(t new-window -d -P -F '#{pane_id}' -t =misc: -c "$D" claude --resume 0000-ctsh)
for _ in $(seq 50); do
  [ -n "$(claude_in "$cpane")" ] && break
  sleep 0.1
done
old=$(claude_in "$cpane")
out=$(run --pane "$SOCK" "$cpane" 2>&1)
rc=$?
[ "$rc" -ne 0 ] && grep -qF "pane $cpane (misc) was not started by" <<<"$out" && [ "$(claude_in "$cpane")" = "$old" ] \
  && pass "restart of a claude that is its pane's process: refused, untouched" || fail "restart of a pane's own claude: rc=$rc ($out)"
[ "$(in_view s "$cpane")" = pane ] && pass "in-view on a pane's own claude not launched here: the pane, for that refusal" \
  || fail "in-view on a pane's own claude: '$(in_view s "$cpane")'"
kill "$old"

# One the session did launch, by the mark in its start command: the session.
cpane=$(t new-window -d -P -F '#{pane_id}' -t =misc: -c "$D" bash -c 'CLAUDE_CODE_DISABLE_AGENT_VIEW=1 exec claude --resume 0000-ctsh')
for _ in $(seq 50); do
  [ -n "$(claude_in "$cpane")" ] && break
  sleep 0.1
done
old=$(claude_in "$cpane")
[ "$(in_view s "$cpane")" = session ] && pass "in-view on a claude the session launched: the session" \
  || fail "in-view on a launched claude: '$(in_view s "$cpane")'"
kill "$old"

# --- what the transcripts say -------------------------------------------------

# A last prompt further back than the tail read for titles, by one long turn.
transcript plan
python3 - "$H/.claude/projects/-proj/0000-ctsh.jsonl" "$D" <<'EOF'
import json, sys
with open(sys.argv[1], "a") as fh:
    for i in range(3):
        print(json.dumps({"type": "assistant", "cwd": sys.argv[2], "uuid": f"f{i}",
                          "timestamp": "2026-01-01T00:02:00.000Z", "message": {"content": "x" * 500000}},
                         separators=(",", ":")), file=fh)
EOF
old=$(hand_start "$bpane" 'claude --resume 0000-ctsh') || exit 1
sh_pid=$(shell_of "$bpane")
out=$(run --pane "$SOCK" "$bpane" 2>&1)
rc=$?
check_restarted "last prompt 1.5 MB back, in plan" "$bpane" "$sh_pid" "$old" \
  "$(printf '%s\n' --resume 0000-ctsh --permission-mode plan)"

# A newer untitled transcript of the same conversation, in another mode: the
# old-form title, canonicalised, and the mode of the id the claude has open.
host=$(hostname)
transcript acceptEdits "$host-old"
sed -e 's/0000-ctsh/0000-newer/' -e 's/"permissionMode":"acceptEdits"/"permissionMode":"plan"/' \
  -e 's/2026-01-01/2026-01-02/' -e '/-title"/d' \
  "$H/.claude/projects/-proj/0000-ctsh.jsonl" >"$H/.claude/projects/-proj/0000-newer.jsonl"
old=$(claude_in "$bpane")
printf '0000-ctsh\n%s\n' "$host-old" >"$WORK/agents.d/$old" # the name it shows, as a /rename leaves it
out=$(run --pane "$SOCK" "$bpane" 2>&1)
rc=$?
check_restarted "a newer untitled transcript folded on, an old-form title" "$bpane" "$sh_pid" "$old" \
  "$(printf '%s\n' --resume 0000-ctsh -n "$host/old" --permission-mode acceptEdits)"
rm "$H/.claude/projects/-proj/0000-newer.jsonl"

# A resume can continue under a new id.
echo 0000-cont >"$WORK/new_id"
old=$(claude_in "$bpane")
out=$(run --pane "$SOCK" "$bpane" 2>&1)
rc=$?
new=$(claude_in "$bpane")
[ "$rc" -eq 0 ] && [ -n "$new" ] && [ "$new" != "$old" ] && grep -qF 'the resume continues under id 0000-cont' <<<"$out" \
  && pass "a resume under a new id: restarted, and said so" || fail "a resume under a new id: rc=$rc, claude $old -> '$new' ($out)"
rm "$WORK/new_id"
kill "$new"

# --- bash and zsh: a name that needs quoting ---------------------------------

name="it's a\\b \$x"
transcript acceptEdits "$name"
printf '%s\n' "$name" >"$WORK/name"
for pane in "$bpane" "$zpane"; do
  old=$(hand_start "$pane" 'claude --resume 0000-ctsh') || exit 1
  sh_pid=$(shell_of "$pane")
  out=$(run --pane "$SOCK" "$pane" 2>&1)
  rc=$?
  check_restarted "a name with ' \\ \$ in $(ps -o comm= -p "$sh_pid")" "$pane" "$sh_pid" "$old" \
    "$(printf '%s\n' --resume 0000-ctsh -n "$name" --permission-mode acceptEdits)"
  kill "$(claude_in "$pane")"
done

# --- fish: the same name, through prefix C-r ---------------------------------

old=$(hand_start "$fpane" 'claude --resume 0000-ctsh') || exit 1
sh_pid=$(shell_of "$fpane")

# The client: attached to sh-fish in a pty, typing what press writes to
# $WORK/client.out.key, its screen in $WORK/client.out, until
# $WORK/client.out.done exists (two minutes at most).
python3 - "$TMUX_BIN" "$SOCK" "$WORK/client.out" "$H" "$P" <<'EOF' &
import os, pty, select, sys, time
tmux, sock, log, home, path = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execve(tmux, [tmux, "-S", sock, "attach", "-t", "=sh-fish"],
              {"HOME": home, "PATH": path, "TERM": "xterm-256color"})
import fcntl, struct, termios
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 160, 0, 0))
t0 = time.time()
with open(log, "wb") as out:
    while time.time() - t0 < 120 and not os.path.exists(log + ".done"):
        try:
            with open(log + ".key", "rb") as f:
                keys = f.read()
            os.remove(log + ".key")
            os.write(fd, keys)
        except FileNotFoundError:
            pass
        if select.select([fd], [], [], 0.1)[0]:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            out.write(data); out.flush()
EOF
client_job=$!
press() {
  printf '%b' "$1" >"$WORK/client.out.key.tmp" && mv "$WORK/client.out.key.tmp" "$WORK/client.out.key"
  for _ in $(seq 40); do
    [ -e "$WORK/client.out.key" ] || return 0
    sleep 0.1
  done
  fail "the client never typed '$1'"
}
# since <byte>: what the client drew from that byte on, escapes stripped;
# wait_for <byte> <text>: until that holds <text>, 20 s at most.
since() { tail -c +"$(($1 + 1))" "$WORK/client.out" | tr -d '\033'; }
wait_for() {
  for _ in $(seq 80); do
    since "$1" | grep -aqF -- "$2" && return 0
    sleep 0.25
  done
  return 1
}
for _ in $(seq 40); do
  [ -n "$(t list-clients -F '#{client_name}')" ] && break
  sleep 0.25
done
[ -n "$(t list-clients -F '#{client_name}')" ] || fail "the client never attached: $(tr -d '\033' <"$WORK/client.out" | tail -c 300)"
sleep 0.5

press '\001\022'
wait_for 0 'any other key' && since 0 | grep -qF ' restart claude in sh-fish:0? ' \
  && since 0 | grep -qF 'Nothing else is running; the restart kills nothing.' \
  && pass "C-r on a claude at fish's prompt: a popup naming sh-fish:0, nothing to kill" \
  || fail "C-r popup: $(since 0 | grep -ao 'restart claude in.\{0,200\}' | head -1)"
press y
wait_for 0 "C-r: pane $fpane (sh-fish): restarted conversation 0000-ctsh" \
  && pass "C-r verdict on the message line" || fail "C-r verdict: $(since 0 | grep -ao 'C-r: [^\[]*' | tail -1)"
rc=0 out="(through prefix C-r)"
check_restarted "prefix C-r, y, in fish, last prompt in acceptEdits, a name with ' \\ \$" "$fpane" "$sh_pid" "$old" \
  "$(printf '%s\n' --resume 0000-ctsh -n "$name" --permission-mode acceptEdits)"

# C-r while scrolled back: the pane is in copy mode, where typed keys would
# be copy-mode commands, so the restart leaves it before typing the resume.
old=$(claude_in "$fpane")
t copy-mode -t "$fpane"
mark=$(wc -c <"$WORK/client.out")
press '\001\022'
wait_for "$mark" 'any other key' || fail "no C-r popup in copy mode: $(since "$mark" | tail -c 300)"
press y
wait_for "$mark" "C-r: pane $fpane (sh-fish): restarted conversation 0000-ctsh" \
  && pass "C-r verdict from copy mode" || fail "C-r from copy mode: pane_in_mode=$(t display -p -t "$fpane" '#{pane_in_mode}'), $(since "$mark" | grep -ao 'C-r: [^\[]*' | tail -1)"
rc=0 out="(through prefix C-r, in copy mode)"
check_restarted "prefix C-r from copy mode" "$fpane" "$sh_pid" "$old" \
  "$(printf '%s\n' --resume 0000-ctsh -n "$name" --permission-mode acceptEdits)"

# C-r at a bare prompt on this server: said so, nothing asked.
t switch-client -t =misc:0
sleep 0.5
mark=$(wc -c <"$WORK/client.out")
press '\001\022'
wait_for "$mark" "C-r: restart: no claude in the foreground of pane $mpane (misc)" \
  && pass "C-r at a bare prompt: said so on the message line" \
  || fail "C-r at a bare prompt: $(since "$mark" | grep -ao 'C-r: [^\[]*' | tail -1)"

# A pane closed before the popup got to it: tmux's formats come out blank.
mark=$(wc -c <"$WORK/client.out")
env -i HOME="$H" PATH="$P" USER="$USER" "$H/.dotfiles/home/.config/tmux/restart-claude.sh" \
  ask "$SOCK" misc "$(t list-clients -F '#{client_name}')" %999
wait_for "$mark" 'C-r: the pane is gone; nothing restarted' && pass "C-r on a pane since closed: said so" \
  || fail "C-r on a closed pane: $(since "$mark" | grep -ao 'C-r: [^\[]*' | tail -1)"
touch "$WORK/client.out.done"

log "$failures failure(s)"
[ "$failures" -eq 0 ]

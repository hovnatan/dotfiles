#!/usr/bin/env bash
# check.sh covers: scripts/periodic.sh
#
# periodic_test.sh -- end-to-end checks for scripts/periodic.sh, the runner
# of recurring tasks. A throwaway HOME holds task directories for the public
# repo and a private one; stubs for osascript and notify-send record each
# notification instead of showing it. Needs gtimeout (coreutils-prefixed);
# about 3 s.
#
#   due          a task never run runs; run again at once, it does not;
#                once its last success is older than its period, it does
#   repos        a private repo's task runs too; a name in both is refused
#   failure      output kept beside the event log, one notification, the
#                task retried on the next run without a second one; a pass
#                then notifies "recovered" and clears the failing state
#   timeout      a task past its `# timeout:` is killed and reported
#   malformed    no period, a bad timeout, not executable: each refused and
#                notified, the other tasks still run, exit 1
#   lock         a run while another is alive leaves without running
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

command -v gtimeout >/dev/null || {
  echo "periodic_test.sh: gtimeout not on PATH (coreutils-prefixed)" >&2
  exit 1
}

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$REPO/scripts/periodic.sh"
WORK=$(mktemp -d)
H="$WORK/home"
PUB="$H/.dotfiles/scripts/periodic"
PRIV="$H/.hov-dotfiles-private/scripts/periodic"
STATE="$H/.local/state/periodic"
NOTES="$WORK/notifications"
mkdir -p "$PUB" "$PRIV" "$WORK/bin"
: >"$NOTES"

failures=0
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}
cleanup() {
  if [ "$failures" -eq 0 ]; then rm -rf "$WORK"; else log "kept work dir: $WORK"; fi
}
trap cleanup EXIT

# Notification stubs: one line per notification, whichever OS this is.
for stub in osascript notify-send; do
  cat >"$WORK/bin/$stub" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${*: -2}" >>"$NOTES"
EOF
  chmod +x "$WORK/bin/$stub"
done

# task <dir> <name> <header lines> <body>: an executable task script.
task() {
  printf '#!/usr/bin/env bash\n%b\n%s\n' "$3" "$4" >"$1/$2.sh"
  chmod +x "$1/$2.sh"
}
run() {
  HOME=$H XDG_STATE_HOME="$H/.local/state" PATH="$WORK/bin:$PATH" "$SCRIPT" >"$WORK/out" 2>&1
}
# ran <name>: how many times the task has run (grep -c prints 0 and fails
# on no match, and prints nothing when the file does not exist yet).
ran() {
  local n
  n=$(grep -c "^$1\$" "$WORK/ran" 2>/dev/null)
  echo "${n:-0}"
}
notes() { grep -c "$1" "$NOTES"; }

# --- due
task "$PUB" weekly '# period: 7d' "echo weekly >>'$WORK/ran'"
task "$PRIV" private '# period: 1d' "echo private >>'$WORK/ran'"
run
if [ "$(ran weekly)" = 1 ] && [ "$(ran private)" = 1 ]; then
  pass "due: never-run tasks ran, the private repo's too"
else
  fail "due: first run: weekly $(ran weekly), private $(ran private): $(cat "$WORK/out")"
fi
run
if [ "$(ran weekly)" = 1 ]; then
  pass "due: not again within its period"
else
  fail "due: ran again at once"
fi
echo $(($(date +%s) - 8 * 86400)) >"$STATE/weekly.last_ok"
run
if [ "$(ran weekly)" = 2 ] && [ "$(ran private)" = 1 ]; then
  pass "due: ran again once its period had passed, the other not"
else
  fail "due: after 8 days: weekly $(ran weekly), private $(ran private)"
fi

# --- repos: one name in two repos
task "$PRIV" weekly '# period: 7d' "echo dup >>'$WORK/ran'"
run
if [ $? -ne 0 ] && grep -q "task 'weekly' is in two places" "$WORK/out" && [ "$(ran dup)" = 0 ]; then
  pass "repos: a name in two repos refused"
else
  fail "repos: duplicate not refused: $(cat "$WORK/out")"
fi
rm "$PRIV/weekly.sh"
: >"$NOTES"

# --- failure, retry, recovery
task "$PUB" flaky '# period: 1d' "echo flaky >>'$WORK/ran'; [ -e '$WORK/fixed' ] || { echo 'disk on fire'; exit 3; }"
run
kept=("$H"/.dotfiles/.logs/*_periodic/*_flaky.log)
if [ -f "${kept[0]}" ] && grep -q 'disk on fire' "${kept[0]}" \
  && [ "$(notes 'flaky failed')" = 1 ] && grep -q 'exit 3: disk on fire' "$NOTES" \
  && [ -e "$STATE/flaky.failing" ]; then
  pass "failure: output kept, one notification with its last line"
else
  fail "failure: kept ${kept[*]}; notes: $(cat "$NOTES"); out: $(cat "$WORK/out")"
fi
run
if [ "$(ran flaky)" = 2 ] && [ "$(notes 'flaky failed')" = 1 ]; then
  pass "failure: retried on the next run, not notified twice"
else
  fail "failure: retry ran $(ran flaky) times, $(notes 'flaky failed') notifications"
fi
touch "$WORK/fixed"
run
if [ "$(ran flaky)" = 3 ] && [ "$(notes 'flaky recovered')" = 1 ] && [ ! -e "$STATE/flaky.failing" ]; then
  pass "failure: a pass notifies recovered and clears the state"
else
  fail "failure: recovery: notes $(cat "$NOTES"); failing $(ls "$STATE")"
fi

# --- timeout: killed at its limit, not after the task's own 600 s
task "$PUB" slow '# period: 1d\n# timeout: 1s' "sleep 600"
start=$(date +%s)
run
if grep -q 'FAIL slow (timed out after 1s' "$WORK/out" && [ $(($(date +%s) - start)) -lt 20 ]; then
  pass "timeout: killed at its 1s limit, reported as timed out"
else
  fail "timeout: $(cat "$WORK/out")"
fi
rm "$PUB/slow.sh"

# --- malformed: each refused, the rest still run
task "$PUB" noperiod '' "echo noperiod >>'$WORK/ran'"
task "$PUB" badtimeout '# period: 1d\n# timeout: soon' "echo badtimeout >>'$WORK/ran'"
task "$PUB" notexec '# period: 1d' "echo notexec >>'$WORK/ran'"
chmod -x "$PUB/notexec.sh"
task "$PUB" fine '# period: 1d' "echo fine >>'$WORK/ran'"
: >"$NOTES"
run
rc=$?
if [ "$rc" -eq 1 ] && [ "$(ran fine)" = 1 ] \
  && [ "$(ran noperiod)$(ran badtimeout)$(ran notexec)" = 000 ] \
  && [ "$(notes 'task problem')" = 3 ]; then
  pass "malformed: three refused and notified, the good task ran, exit 1"
else
  fail "malformed: rc $rc, fine $(ran fine), notes $(cat "$NOTES"), out $(cat "$WORK/out")"
fi
rm "$PUB"/noperiod.sh "$PUB"/badtimeout.sh "$PUB"/notexec.sh

# --- lock: a live owner makes the run leave
rm -f "$STATE/fine.last_ok"
mkdir "$STATE/.lock" && echo $$ >"$STATE/.lock/pid"
run
if grep -q "another run (pid $$) is still going" "$WORK/out" && [ "$(ran fine)" = 1 ]; then
  pass "lock: a run while another is alive left without running"
else
  fail "lock: $(cat "$WORK/out")"
fi
rm -rf "$STATE/.lock"

log "$([ "$failures" -eq 0 ] && echo "all passed" || echo "$failures failed")"
exit $((failures > 0))

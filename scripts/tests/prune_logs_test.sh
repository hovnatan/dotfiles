#!/usr/bin/env bash
# check.sh covers: scripts/prune_logs.sh scripts/lib/*
#
# prune_logs_test.sh -- end-to-end checks for scripts/prune_logs.sh, which
# removes old event logs from ~/.dotfiles/.logs. Runs the script for real on
# a throwaway HOME whose .logs holds one directory per rule. Needs python3
# (to date the files); about 1 s.
#
#   directory                          holds              written   expect
#   20250101_000000_old                events.log         40 days   removed
#   20250102_000000_old                events.log         40 days   removed
#   20250103_000000_old                events.log         40 days   kept: newest of "old"
#   20250101_000000_young              events.log         5 days    kept: not old enough
#   20250102_000000_young              events.log         today     kept
#   20250101_000000_record             events.log, README 40 days   kept: a record
#   20250102_000000_record             events.log, sub/   40 days   kept: a record
#   20250103_000000_record             events.log         today     (the newest of "record")
#   20250101_000000_empty              nothing            40 days   kept: no event log
#   20250102_000000_empty              events.log         today     (the newest of "empty")
#   20250101_000000_linked             events.log -> file 40 days   kept: not a file
#   20250102_000000_linked             events.log         today     (the newest of "linked")
#   notes                              events.log         40 days   kept: not the form
#   2025_notes_b                       events.log         40 days   kept: not the form
#
#   once a day   a second run the same day does nothing; --force does, and
#                so does a run on another day
#   own log      a run that removed something logs what; one that did not
#                leaves no directory
#   nothing of   a .logs with no directory of the form is not an error
#   the form
#   log start    a script starting its log (scripts/lib/event_log.sh) prunes
#                if no prune ran today, and not with --no-prune
#   arguments    an unknown one fails
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

command -v python3 >/dev/null || {
  echo "prune_logs_test.sh: python3 not on PATH" >&2
  exit 1
}

REPO=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$REPO/scripts/prune_logs.sh"
WORK=$(mktemp -d)
H="$WORK/home"
L="$H/.dotfiles/.logs"

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

run() { env -i HOME="$H" PATH=/usr/bin:/bin "$SCRIPT" "$@" >"$WORK/out" 2>&1; }
# age <days> <path>...: set the last write of each to that many days ago
age() {
  python3 -c 'import os, sys, time
t = time.time() - float(sys.argv[1]) * 86400
for p in sys.argv[2:]: os.utime(p, (t, t), follow_symlinks=False)' "$@"
}
# event_log <directory> <days>: an event log last written that long ago
event_log() {
  mkdir -p "$L/$1"
  echo "2025-01-01T00:00:00Z something" >"$L/$1/events.log"
  age "$2" "$L/$1/events.log"
}
# What .logs holds, one name a line, without the prune's own stamp and log.
left() {
  local d
  for d in "$L"/*; do
    case "$d" in *_prune_logs) ;; *) basename "$d" ;; esac
  done | sort
}
own_logs() { ls -d "$L"/*_prune_logs 2>/dev/null; }
# For a failure: what the run printed and what it left.
state() { printf '%s; left: %s' "$(cat "$WORK/out")" "$(left | tr '\n' ' ')"; }

# --- no .logs at all ----------------------------------------------------------

mkdir -p "$H"
if run; then
  fail "no .logs: passed"
elif grep -q '.logs missing' "$WORK/out"; then
  pass "no .logs is an error"
else
  fail "no .logs: $(cat "$WORK/out")"
fi

# --- one directory per rule -----------------------------------------------------

mkdir -p "$L"
event_log 20250101_000000_old 40
event_log 20250102_000000_old 40
event_log 20250103_000000_old 40
event_log 20250101_000000_young 5
event_log 20250102_000000_young 0
event_log 20250101_000000_record 40
echo "what was found" >"$L/20250101_000000_record/README.md"
event_log 20250102_000000_record 40
mkdir "$L/20250102_000000_record/sub"
event_log 20250103_000000_record 0
mkdir "$L/20250101_000000_empty"
event_log 20250102_000000_empty 0
mkdir "$L/20250101_000000_linked"
echo "elsewhere" >"$WORK/elsewhere.log"
ln -s "$WORK/elsewhere.log" "$L/20250101_000000_linked/events.log"
age 40 "$WORK/elsewhere.log" "$L/20250101_000000_linked/events.log"
event_log 20250102_000000_linked 0
event_log notes 40
event_log 2025_notes_b 40
left | grep -v -E '^2025010[12]_000000_old$' >"$WORK/expected"

if run; then
  if left >"$WORK/after" && diff "$WORK/expected" "$WORK/after" >"$WORK/diff"; then
    pass "only the two old event logs that are not the newest went ($(wc -l <"$WORK/after" | tr -d ' ') kept)"
  else
    fail "kept the wrong ones (< expected, > found): $(cat "$WORK/diff")"
  fi
else
  fail "prune failed: $(cat "$WORK/out")"
fi
[ -f "$WORK/elsewhere.log" ] && pass "a linked events.log and its target are left alone" \
  || fail "the target of a linked events.log is gone"

# --- its own log ------------------------------------------------------------------

own=$(own_logs | head -1)
if [ -n "$own" ] && [ "$(grep -c ' removed 2025010[12]_000000_old$' "$own/events.log")" -eq 2 ] \
  && grep -q 'removed 2 event log' "$own/events.log"; then
  pass "own log names both and counts them"
else
  fail "own log: $(cat "$own/events.log" 2>&1)"
fi

# --- once a day -------------------------------------------------------------------

rm -rf "$own"
event_log 20250101_000000_old 40
if run && [ -d "$L/20250101_000000_old" ] && [ -z "$(own_logs)" ]; then
  pass "a second run the same day does nothing and leaves no log"
else
  fail "second run: $(state)"
fi
if run --force && [ ! -d "$L/20250101_000000_old" ]; then
  pass "--force prunes the same day"
else
  fail "--force: $(state)"
fi
rm -rf "$L"/*_prune_logs
echo 20250101 >"$L/.pruned"
event_log 20250101_000000_old 40
if run && [ ! -d "$L/20250101_000000_old" ]; then
  pass "a run on a day after the last prunes"
else
  fail "a day after: $(state)"
fi

# --- nothing to do ------------------------------------------------------------------

rm -rf "$L"/*_prune_logs
if run --force && [ -z "$(own_logs)" ]; then
  pass "a run with nothing to remove leaves no log"
else
  fail "nothing to do: $(state)"
fi

# --- a script starting its log ------------------------------------------------------

# What a logging script does, nothing more: start its log, write a line.
start_log() {
  env -i HOME="$H" PATH=/usr/bin:/bin bash -c '. "$1"; shift; event_log_start "$@" && log "a line"' \
    _ "$REPO/scripts/lib/event_log.sh" "$@" >"$WORK/out" 2>&1
}
event_log 20250101_000000_old 40
if start_log probe && [ -d "$L/20250101_000000_old" ] && grep -q ' a line$' "$L"/*_probe/events.log; then
  pass "log start: no prune when one ran today"
else
  fail "log start, pruned today: $(state)"
fi
echo 20250101 >"$L/.pruned"
if start_log probe --no-prune && [ -d "$L/20250101_000000_old" ]; then
  pass "log start: no prune with --no-prune"
else
  fail "log start, --no-prune: $(state)"
fi
if start_log probe && [ ! -d "$L/20250101_000000_old" ] && [ "$(cat "$L/.pruned")" = "$(date -u +%Y%m%d)" ]; then
  pass "log start: prunes when none ran today, and notes the day"
else
  fail "log start, not pruned today: $(state)"
fi

# --- nothing of the form ------------------------------------------------------------

rm -rf "$L"
mkdir -p "$L/notes"
if run --force; then
  pass "a .logs with no directory of the form is not an error"
else
  fail "nothing of the form: exit $?: $(state)"
fi

# --- arguments --------------------------------------------------------------------

if run --all; then
  fail "arguments: --all was taken"
elif grep -q "unknown argument '--all'" "$WORK/out"; then
  pass "arguments: an unknown one fails"
else
  fail "arguments: $(cat "$WORK/out")"
fi

log "$failures failure(s)"
[ "$failures" -eq 0 ]

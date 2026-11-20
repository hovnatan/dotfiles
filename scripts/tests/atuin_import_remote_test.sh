#!/usr/bin/env bash
#
# atuin_import_remote_test.sh -- end-to-end checks for
# scripts/atuin_import_remote.sh. Two throwaway HOMEs stand for this machine
# and the remote; an `ssh` stub on PATH runs the remote half in the second
# HOME, so atuin and sqlite3 run for real on both sides. Sync is never
# touched (--no-sync): nothing is logged in. Needs atuin and sqlite3; ~5 s.
#
#   remote row                                   expect
#   native, finished (ns duration, exit 2)       imported, every field equal
#   from `atuin import fish` (cwd unknown, -1)   imported
#   native, no duration, started 30 days ago     imported (abandoned)
#   native, no duration, started now             skipped (still running)
#   deleted                                      skipped
#
#   records      imported rows survive `atuin store rebuild history` from
#                an empty history.db, so they would sync
#   re-run       inserts nothing; once the running row finishes, inserts it
#   schema       a column missing on the remote fails the run, naming it
#   log          the run writes its events.log
#   arguments    none, or two hosts, is a usage error (exit 2)
#
# Exit 0 = all passed; on failure the work dir is kept and printed.

set -uo pipefail

for tool in atuin sqlite3; do
  command -v "$tool" >/dev/null || {
    echo "atuin_import_remote_test.sh: $tool not on PATH" >&2
    exit 1
  }
done

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
SCRIPT="$REPO/scripts/atuin_import_remote.sh"
WORK=$(mktemp -d)
LOCAL="$WORK/local"
REMOTE="$WORK/remote"
mkdir -p "$LOCAL" "$REMOTE" "$WORK/bin"

trap drop_work EXIT

# ssh stub: drop the options and the host, run the rest in the remote HOME.
# `bash -l` loses its -l: a login profile is the real machine's concern.
cat >"$WORK/bin/ssh" <<EOF
#!/usr/bin/env bash
while [ "\$1" = -o ]; do shift 2; done
shift
args=()
for a in "\$@"; do [ "\$a" = -l ] || args+=("\$a"); done
exec env HOME="$REMOTE" "\${args[@]}"
EOF
chmod +x "$WORK/bin/ssh"

# record <home> <host> <exit> <command>: one native row, as a shell hook
# writes it (start, then end with the exit code).
record() {
  local id
  id=$(HOME=$1 ATUIN_HOST_NAME=$2 ATUIN_HOST_USER=azure atuin history start -- "$4")
  HOME=$1 atuin history end --exit "$3" -- "$id" >/dev/null 2>&1
}
export ATUIN_SESSION
ATUIN_SESSION=$(atuin uuid)

# run [args...]: the script as this machine, the stub ssh first on PATH.
run() {
  HOME=$LOCAL PATH="$WORK/bin:$PATH" "$SCRIPT" "$@" >"$WORK/out" 2>&1
}

# The remote's rows: one native and finished, the rest written as atuin
# would leave them (columns by name; ids are 32 hex digits, as atuin parses
# them; author and shell set, as on every real row: a rebuild fills an empty
# author in from the user).
record "$LOCAL" localbox 0 "echo local"
record "$REMOTE" remotebox 2 "make test"
now_ns=$(($(date +%s) * 1000000000))
old_ns=$((now_ns - 30 * 86400 * 1000000000))
sqlite3 "$REMOTE/.atuin/data/history.db" <<EOF
insert into history (id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, shell)
values
  ('01a1e4f40000000000000000000000f1', $old_ns - 1, -1, -1, 'echo from-fish', 'unknown', 's1', 'remotebox:azure', null, 'azure', 'fish'),
  ('01a1e4f40000000000000000000000a2', $old_ns, -1, -1, 'sleep 99999', '/proj', 's2', 'remotebox:azure', null, 'azure', 'fish'),
  ('01a1e4f40000000000000000000000c3', $now_ns, -1, -1, 'tail -f log', '/proj', 's3', 'remotebox:azure', null, 'azure', 'fish'),
  ('01a1e4f40000000000000000000000d4', $old_ns + 1, 5, 0, 'echo secret', '/proj', 's4', 'remotebox:azure', $now_ns, 'azure', 'fish');
EOF

# rows <home> [where]: the copied columns of matching rows, sorted.
COLS="id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind"
rows() {
  sqlite3 "$1/.atuin/data/history.db" "select $COLS from history where ${2:-1} order by id"
}

# --- first run: the three eligible rows, every field equal
if run remotebox --no-sync && grep -q 'inserted 3 new rows' "$WORK/out"; then
  pass "first run inserted 3"
else
  fail "first run: $(cat "$WORK/out")"
fi
want=$(rows "$REMOTE" "hostname like 'remotebox:%' and id not in ('01a1e4f40000000000000000000000c3', '01a1e4f40000000000000000000000d4')")
got=$(rows "$LOCAL" "hostname like 'remotebox:%'")
if [ -n "$want" ] && [ "$want" = "$got" ]; then
  pass "imported rows equal the remote's, field for field"
else
  fail "imported rows differ:"$'\n'"want: $want"$'\n'"got:  $got"
fi
if [ "$(rows "$LOCAL" "command in ('tail -f log', 'echo secret')")" = "" ]; then
  pass "running and deleted rows skipped"
else
  fail "running or deleted row imported"
fi
if [ "$(rows "$LOCAL" "hostname like 'remotebox:%' and command = 'make test' and duration > 0 and exit = 2")" != "" ]; then
  pass "native row keeps its nanosecond duration and exit code"
else
  fail "native row lost its duration or exit code"
fi

# --- records: history.db rebuilt from the store alone keeps them
before=$(rows "$LOCAL")
rm -f "$LOCAL/.atuin/data/history.db"*
HOME=$LOCAL atuin store rebuild history >/dev/null 2>&1
if [ "$(rows "$LOCAL")" = "$before" ]; then
  pass "rows survive a rebuild from the record store"
else
  fail "rebuild from the store lost rows:"$'\n'"before: $before"$'\n'"after:  $(rows "$LOCAL")"
fi

# --- re-run: nothing new; then the running row finishes and comes over
if run remotebox --no-sync && grep -q 'inserted 0 new rows' "$WORK/out"; then
  pass "re-run inserted nothing"
else
  fail "re-run: $(cat "$WORK/out")"
fi
sqlite3 "$REMOTE/.atuin/data/history.db" \
  "update history set duration = 1500000, exit = 0 where id = '01a1e4f40000000000000000000000c3'"
if run remotebox --no-sync && grep -q 'inserted 1 new rows' "$WORK/out" \
  && [ "$(rows "$LOCAL" "command = 'tail -f log' and duration = 1500000")" != "" ]; then
  pass "finished row imported on the next run"
else
  fail "finished row: $(cat "$WORK/out")"
fi

# --- log: each run wrote its events.log
if grep -qs 'inserted 3 new rows' "$LOCAL"/.dotfiles/.logs/*_atuin_import_remote/events.log; then
  pass "events.log written"
else
  fail "no events.log with the first run's line under $LOCAL/.dotfiles/.logs"
fi

# --- schema: a column gone on the remote stops the run, naming it
sqlite3 "$REMOTE/.atuin/data/history.db" 'alter table history drop column author_kind'
if ! run remotebox --no-sync && grep -q "column 'author_kind' missing" "$WORK/out"; then
  pass "missing column fails the run"
else
  fail "missing column: $(cat "$WORK/out")"
fi

# --- arguments
for args in "" "a b"; do
  # shellcheck disable=SC2086 # split on purpose: "" is no argument at all
  HOME=$LOCAL "$SCRIPT" $args >/dev/null 2>&1
  if [ $? -eq 2 ]; then pass "usage error for '$args'"; else fail "no usage error for '$args'"; fi
done

finish

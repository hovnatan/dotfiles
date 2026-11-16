#!/usr/bin/env bash
# atuin_import_remote.sh <host> [--no-sync] -- copy another machine's atuin
# history into this one's, every field intact (nanosecond durations, exit
# codes, directories, sessions, host), then sync it to this machine's atuin
# account. For a machine that is deliberately not logged in to sync (it never
# sees this machine's key or history), run here by hand from time to time.
#
#   <host> ~/.atuin/data/history.db
#      |  sqlite3 .backup on <host> (a consistent copy of a live database),
#      |  streamed back over ssh into a temp dir here
#      v
#   snapshot --insert or ignore--> history.db here    (rows keep their own ids,
#      |                                                so a re-run adds only
#      |                                                what is new)
#      v
#   atuin history init-store   new rows -> encrypted records in records.db
#   atuin sync                 records -> the account (skipped with --no-sync)
#
# Why rows rather than `atuin import`: no importer reads atuin's own
# database, and the nearest (zsh-hist-db) keeps durations in whole seconds.
# This writes into atuin's history.db directly, the one step past atuin's CLI;
# init-store, sync and any later `atuin store rebuild history` are atuin's own.
# Both databases must have every column in COPY_COLUMNS, so a schema change in a
# future atuin fails here instead of importing half a row.
#
# Which rows: everything in <host>'s history.db not deleted there, except a
# command still running there (a native row with no duration yet, started in
# the last 7 days): imported now it would keep "unknown" forever, while left
# alone it comes over complete on a later run. Rows from `atuin import fish`
# (cwd "unknown", no duration ever) and older native rows without one (a
# shell killed mid-command) are imported as they are.
#
# Needs atuin and sqlite3 on both machines (nix/flake.nix) and ssh to <host>
# without a prompt. Each run logs to ~/.dotfiles/.logs/<UTC>_atuin_import_remote/.
#
#   scripts/atuin_import_remote.sh <host>
#   -> ... snapshot: 512 rows (deleted 0, running 1)
#      ... inserted 17 new rows (494 already here)
#      ... records: 932 -> 949
#      ... sync: 17/0 up/down to record store

set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <host> [--no-sync]" >&2
  exit 2
}

host=
sync=1
for arg in "$@"; do
  case $arg in
    --no-sync) sync=0 ;;
    -*) usage ;;
    *)
      [ -z "$host" ] || usage
      host=$arg
      ;;
  esac
done
[ -n "$host" ] || usage

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/lib/event_log.sh"
event_log_start atuin_import_remote

die() {
  log "FAIL $*" >&2
  exit 1
}

# The columns copied, by name: every one atuin 18.24 has. A missing one on
# either side stops the run (see the header).
COPY_COLUMNS="id, timestamp, duration, exit, command, cwd, session, hostname, deleted_at, author, intent, shell, author_kind"

for tool in atuin sqlite3 ssh; do
  command -v "$tool" >/dev/null || die "$tool not on PATH; it comes from nix/flake.nix (nix profile upgrade nix)"
done
# atuin's subcommands want a session id even when they record nothing
export ATUIN_SESSION="${ATUIN_SESSION:-$(atuin uuid)}"
local_db=$(atuin config get --resolved db_path)
records_db=$(atuin config get --resolved record_store_path)
[ -f "$local_db" ] || die "no atuin history here at $local_db; open a shell with atuin loaded first"
log "start: $host -> $local_db"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
snap="$work/history.db"

# Snapshot on <host>. A plain copy of a database atuin may be writing can
# catch it mid-transaction; sqlite's .backup cannot. The remote side prints
# only the file on stdout, so anything else there (a chatty login profile)
# fails the integrity check below rather than slipping in.
log "snapshot: $host"
ssh -o ConnectTimeout=15 "$host" bash -l -s >"$snap" <<'EOF' || die "snapshot on $host failed (its message is above)"
set -euo pipefail
for tool in atuin sqlite3; do
  command -v "$tool" >/dev/null || { echo "$(hostname): $tool not on PATH; update this machine (dotup)" >&2; exit 1; }
done
db=$(atuin config get --resolved db_path)
[ -f "$db" ] || { echo "$(hostname): no atuin history at $db" >&2; exit 1; }
t=$(mktemp)
trap 'rm -f "$t"' EXIT
sqlite3 -cmd '.timeout 10000' "$db" ".backup '$t'"
cat "$t"
EOF
check=$(sqlite3 "$snap" 'pragma quick_check' 2>&1) || true
[ "$check" = ok ] || die "snapshot from $host is not a sound sqlite database ($check); something on $host may print to stdout at login"

for db in "$snap" "$local_db"; do
  have=$(sqlite3 "$db" "select name from pragma_table_info('history')")
  for col in ${COPY_COLUMNS//,/}; do
    grep -qx "$col" <<<"$have" || die "column '$col' missing from history in $db: atuin's schema changed; compare COPY_COLUMNS here with: sqlite3 $db '.schema history'"
  done
done

# The row filter, shared by the counts and the insert. "Running": a native
# row (a real cwd) with no duration yet, started less than 7 days ago.
recent_ns="(strftime('%s', 'now') - 7 * 86400) * 1000000000"
running="duration < 0 and cwd != 'unknown' and timestamp > $recent_ns"
read -r total deleted skipped < <(sqlite3 -separator ' ' "$snap" \
  "select count(*), count(deleted_at), coalesce(sum(deleted_at is null and $running), 0) from history")
log "snapshot: $total rows (deleted $deleted, running $skipped)"

# The insert. `or ignore` skips a row already here: same id from an earlier
# run, or the same (timestamp, cwd, command), atuin's own unique key.
inserted=$(
  sqlite3 "$local_db" <<EOF
.timeout 10000
attach '$snap' as remote;
insert or ignore into main.history ($COPY_COLUMNS)
  select $COPY_COLUMNS from remote.history
  where deleted_at is null and not ($running);
select changes();
EOF
)
log "inserted $inserted new rows ($((total - deleted - skipped - inserted)) already here)"

# History rows sync only as records: init-store encrypts every row that has
# none yet, the new ones included.
before=$(sqlite3 "$records_db" "select count(*) from store where tag = 'history'")
atuin history init-store >"$work/init-store.log" 2>&1 || {
  cat "$work/init-store.log" >&2
  die "atuin history init-store failed (output above)"
}
after=$(sqlite3 "$records_db" "select count(*) from store where tag = 'history'")
log "records: $before -> $after"
[ $((after - before)) -ge "$inserted" ] \
  || die "init-store added $((after - before)) records for $inserted new rows; they would not sync"

if [ "$sync" -eq 0 ]; then
  log "done; sync skipped (--no-sync), the next automatic one uploads them"
  exit 0
fi
sync_out=$(atuin sync 2>&1) || {
  printf '%s\n' "$sync_out" >&2
  die "atuin sync failed (output above); the rows are imported here, run atuin sync again"
}
log "sync: $(grep 'up/down' <<<"$sync_out" || tail -n 1 <<<"$sync_out")"
log "done"

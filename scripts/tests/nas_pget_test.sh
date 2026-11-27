#!/usr/bin/env bash
#
# nas_pget_test.sh -- checks for scripts/nas_pget.sh, which pulls a file from
# the NAS block by block. No NAS and no network: an lftp of the test's own is
# first on PATH. It answers `cls` with the size of a local source file and, for
# `pget`, copies from it the pieces the status file lists, as lftp does; told
# to (STOP_AT), it stops half-way through a call, the status file rewritten to
# the pieces left, as a killed lftp leaves it.
#
#   source  40 MiB + 12345 bytes, NAS_PGET_BLOCK_MB=8, so the blocks are
#           [24 MiB + 12345, end)  the tail, first
#           [0, 8 MiB)  [8, 16 MiB)  [16 MiB, 24 MiB + 12345)
#
#   fresh        the four blocks in that order, 16 pieces each, the copy equal
#                to the source, no status or state file left, the run in the
#                event log
#   again        a second run fetches nothing and says the file is complete
#   interrupted  lftp dying in the third block: status 1, the state file names
#                that block; the next run fetches only what was left of it,
#                then the last block
#   empty status the status file emptied (lftp killed while rewriting it): the
#                block is fetched again from its start
#   stale status a status file with no download beside it is not resumed
#   refusals     a file of another size already there, a download lftp began
#                alone, a NAS file whose size changed since the start, a file
#                the NAS does not have: status 1 and nothing fetched
#   arguments    none: status 2; a URL that is not sftp, has no path, or a
#                path alone: status 1
#
# Exit 0 = all passed; a failed check prints the output it looked at.

set -uo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"

SCRIPT="$REPO/scripts/nas_pget.sh"
WORK=$(mktemp -d)
trap drop_work EXIT
OUT="$WORK/out"
SRC="$WORK/nas/film.mkv"
export CALLS="$WORK/calls" SRC
M=1048576
SIZE=$((40 * M + 12345))
TAIL=$((SIZE - 16 * M))

# lib.sh's, and the output the check looked at
fail() {
  log "FAIL $*"
  sed 's/^/    | /' "$OUT"
  failures=$((failures + 1))
}

mkdir -p "$WORK/bin" "$WORK/nas" "$WORK/home"
head -c "$SIZE" /dev/urandom >"$SRC"
cat >"$WORK/bin/lftp" <<'FAKE'
#!/usr/bin/env python3
import os, re, sys

command, src, calls = sys.argv[2], os.environ["SRC"], os.environ["CALLS"]
with open(calls + ".url", "w") as f:
    f.write(sys.argv[3] + "\n")
path = re.search(r"(?:cls|pget) [^']*'([^']*)'", command).group(1)
name = os.path.basename(path)
if os.path.basename(src) != name or not os.path.exists(src):
    sys.exit(f"Access failed: No such file ({path})")
if " cls " in command:
    print(f"  {os.path.getsize(src)} {path}")
    sys.exit(0)

status = name + ".lftp-pget-status"
values = dict(line.split("=") for line in open(status).read().split())
pieces = []
while f"{len(pieces)}.pos" in values:
    i = len(pieces)
    pieces.append((int(values[f"{i}.pos"]), int(values[f"{i}.limit"])))
with open(calls, "a") as f:
    f.write(f"{len(pieces)} pieces [{min(p for p, _ in pieces)},{max(l for _, l in pieces)})\n")
call = sum(1 for _ in open(calls))
stop = int(os.environ.get("STOP_AT", "0")) == call

open(name, "ab").close()
left = []
with open(src, "rb") as s, open(name, "r+b") as d:
    for i, (pos, limit) in enumerate(pieces):
        if stop and i >= len(pieces) // 2:
            left.append((pos, limit))
            continue
        s.seek(pos)
        d.seek(pos)
        d.write(s.read(limit - pos))
if stop:
    with open(status, "w") as f:
        f.write(f"size={values['size']}\n")
        for i, (pos, limit) in enumerate(left):
            f.write(f"{i}.pos={pos}\n{i}.limit={limit}\n")
    sys.exit(1)
os.remove(status)
FAKE
chmod +x "$WORK/bin/lftp"

# pget [VAR=value...] [-- args]: nas_pget.sh for film.mkv into $DEST, or with
# the arguments after --; output in $OUT, status in $rc
pget() {
  local -a env=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    env+=("$1")
    shift
  done
  if [ $# -gt 0 ]; then shift; else set -- sftp://u@nas:22/video/film.mkv "$DEST"; fi
  env HOME="$WORK/home" PATH="$WORK/bin:$PATH" \
    NAS_PGET_BLOCK_MB=8 "${env[@]}" "$SCRIPT" "$@" >"$OUT" 2>&1
  rc=$?
}
# dest <name>: a new empty destination, and no calls recorded
dest() {
  DEST="$WORK/$1"
  mkdir "$DEST"
  : >"$CALLS"
}
expect() {
  if [ "$rc" -eq "$1" ]; then pass "$2: status $1"; else fail "$2: status $rc, expected $1"; fi
}
says() {
  if grep -qF -- "$1" "$OUT"; then pass "$2"; else fail "$2: output lacks '$1'"; fi
}
# called <name> <line>...: the pget calls lftp got are exactly those lines
called() {
  local name=$1
  shift
  if [ "$(printf '%s\n' "$@")" = "$(cat "$CALLS")" ]; then
    pass "$name"
  else
    fail "$name: lftp was called with: $(tr '\n' ';' <"$CALLS")"
  fi
}
# complete <name>: the copy equals the source and nothing is left beside it
complete() {
  if cmp -s "$SRC" "$DEST/film.mkv" && [ "$(ls -A "$DEST")" = film.mkv ]; then
    pass "$1: the copy equals the source, alone in its directory"
  else
    fail "$1: the copy differs or has files beside it: $(ls -A "$DEST" | tr '\n' ' ')"
  fi
}

# --- fresh, again -----------------------------------------------------------------

dest fresh
pget
expect 0 fresh
called "fresh: the tail, then the blocks in file order" \
  "16 pieces [$TAIL,$SIZE)" "16 pieces [0,$((8 * M)))" \
  "16 pieces [$((8 * M)),$((16 * M)))" "16 pieces [$((16 * M)),$TAIL)"
complete fresh
says "playable from the start up to 8 of 40 MiB (19%)" "fresh: reports how far it plays"
if [ "$(cat "$CALLS.url")" = sftp://u:dummy@nas:22 ]; then
  pass "fresh: lftp opens the URL's server, with the unused password"
else
  fail "fresh: lftp was given: $(cat "$CALLS.url")"
fi
if grep -qF "done: $DEST/film.mkv" "$WORK"/home/.dotfiles/.logs/*_nas_pget/events.log; then
  pass "fresh: the run is in the event log"
else
  fail "fresh: no done line in the event log"
fi

: >"$CALLS"
pget
expect 0 again
says "already complete" "again: says the file is complete"
called "again: nothing fetched" ""

# --- interrupted ------------------------------------------------------------------

dest interrupted
pget STOP_AT=3
expect 1 interrupted
says "run the same command again" "interrupted: says how to carry on"
if [ "$(cat "$DEST/film.mkv.nas-pget-next")" = "$SIZE $((8 * M))" ]; then
  pass "interrupted: the state file names the third block"
else
  fail "interrupted: state file is '$(cat "$DEST/film.mkv.nas-pget-next")'"
fi
: >"$CALLS"
pget
expect 0 resumed
called "resumed: what was left of the block, then the last one" \
  "8 pieces [$((12 * M)),$((16 * M)))" "16 pieces [$((16 * M)),$TAIL)"
complete resumed

# --- empty status, stale status ---------------------------------------------------

dest empty_status
pget STOP_AT=2
: >"$DEST/film.mkv.lftp-pget-status"
: >"$CALLS"
pget
expect 0 "empty status"
called "empty status: the block again from its start, then the rest" \
  "16 pieces [0,$((8 * M)))" "16 pieces [$((8 * M)),$((16 * M)))" "16 pieces [$((16 * M)),$TAIL)"
complete "empty status"

dest stale_status
pget STOP_AT=1
rm "$DEST/film.mkv"
: >"$CALLS"
pget
expect 0 "stale status"
if [ "$(head -n 1 "$CALLS")" = "16 pieces [$TAIL,$SIZE)" ]; then
  pass "stale status: the tail is fetched whole"
else
  fail "stale status: first call was: $(head -n 1 "$CALLS")"
fi
complete "stale status"

# --- refusals ---------------------------------------------------------------------

dest other_size
echo short >"$DEST/film.mkv"
pget
expect 1 "another size"
says "has 6 bytes and the NAS file $SIZE" "another size: names both sizes"
called "another size: nothing fetched" ""

dest foreign
: >"$DEST/film.mkv"
echo "size=$SIZE" >"$DEST/film.mkv.lftp-pget-status"
pget
expect 1 "lftp's own download"
says "a download this script did not begin" "lftp's own download: says so"
called "lftp's own download: nothing fetched" ""

dest resized
pget STOP_AT=2
: >"$CALLS"
head -c 100 /dev/urandom >>"$SRC"
pget
expect 1 "size changed"
says "was $SIZE when this download began" "size changed: says so"
called "size changed: nothing fetched" ""
head -c "$SIZE" /dev/urandom >"$SRC"

dest missing
pget -- sftp://u@nas:22/video/absent.mkv "$DEST"
expect 1 "not on the NAS"
says "could not list /video/absent.mkv" "not on the NAS: says so"

# --- arguments --------------------------------------------------------------------

pget --
expect 2 "no arguments"
pget -- fish://u@nas/video/film.mkv "$DEST"
expect 1 "a URL that is not sftp"
pget -- sftp://u@nas:22 "$DEST"
expect 1 "a URL with no path"
pget -- video/film.mkv "$DEST"
expect 1 "a path with no URL"

finish

#!/usr/bin/env bash
#
# nas_pget.sh -- pull one large file from the home NAS over sftp, fast, on a
# lossy long-haul path, in file order so it can be watched while it arrives.
#
#   ~/.dotfiles/scripts/nas_pget.sh 'sftp://user@host:port/share/path/to/file' [dest_dir]
#
# The path is taken as written, spaces and all: quote the URL, do not
# percent-encode it.
#
# Run the same command again to carry on after an interruption.
# NAS_PGET_BLOCK_MB (default 200) is the block size below, in MiB.
#
# Why this exists (measured 2026-09-04, Armenia -> US east coast, 150 ms RTT):
# the return path drops ~0.5% of packets at a congested carrier handoff, which
# caps any single TCP flow at ~0.4 MB/s. Throughput therefore comes from flow
# count. lftp's pget pulls a file as N segments, each over its own ssh
# connection (~2-3 MB/s with 16), and records every segment's offset in a
# `<file>.lftp-pget-status` file next to the download, so a segment whose
# connection dies resumes where it stopped. rclone's multi-thread copy gets the
# same rate but a mid-chunk connection death is fatal for the whole file, and
# connections on this path die every 10-30 minutes.
#
# Left to itself pget cuts the whole file into 16 and fills them side by side,
# so the first minutes of a film are complete only when all of it is. Here the
# file goes in blocks, one after another, and pget is pointed at a block by
# writing its status file for it: the block's range as 16 pieces, which is
# what pget would find had it been interrupted with only those left.
#
#   block 1     the last 16 MiB: an mp4's moov atom or an mkv's cues, which a
#               player wants before it plays or seeks
#   block 2..   200 MiB each, from the start of the file
#
#   16 x [ssh -> sftp-server]  ==lossy WAN==>  lftp pget  -->  <dest>/<name>
#
#   <name>                    full size from block 1 on, a hole where a block
#                             has not come yet
#   <name>.lftp-pget-status   lftp's: the pieces left of the block in flight
#   <name>.nas-pget-next      this script's: the file's size and the block in
#                             flight ("tail" or its offset); gone when done
#
# Blocks came at 1.5-1.8 MiB/s on 2026-11-27, about twice the 0.8 MiB/s a
# 1080p rip plays at, so a player started after block 2 stays behind the
# download, as long as it reads little ahead: a hole reads as zeros at once,
# and mpv with cache=yes and demuxer-max-bytes=1024MiB read 1 GiB ahead into
# one, took it for a corrupt file and skipped to the end. mpv's defaults (1 s
# of read-ahead on a local file) played a file with 300 MiB of it here.
#
# DSM refuses the sftp subsystem ("subsystem request failed") unless "Enable
# SFTP service" is ticked under Control Panel > File Services > FTP. With it
# off, lftp's fish protocol does the same job over the plain ssh login, a
# little less steadily: fish:// in place of sftp:// below, fish:connect-program
# in place of sftp:connect-program, and in the URL the file's path on the NAS's
# disk (/volume1/share/...) instead of the one from the share.
#
# The URL is an argument, not written here: this repo is public and the
# address, port and user name of a home NAS do not belong in it. lftp is given
# it with a password, "dummy", that is never used (ssh authenticates with the
# key): without one lftp falls back to an anonymous login as the local user.
#
# Requires: lftp (nix/flake.nix), key-based ssh auth to the NAS.

set -euo pipefail

usage() {
  echo "usage: $0 'sftp://user@host[:port]/share/path/to/file' [dest_dir]" >&2
  exit 2
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
url=$1
dest_dir=${2:-.}
[[ $url =~ ^sftp://([^/@]+)@([^/@]+)(/.*[^/])$ ]] || {
  echo "not a URL of the form sftp://user@host[:port]/share/path/to/file, got: ${url%%://*}://..." >&2
  exit 1
}
login=${BASH_REMATCH[1]}
nas_url=sftp://$login@${BASH_REMATCH[2]}
[[ $login == *:* ]] || nas_url=sftp://$login:dummy@${BASH_REMATCH[2]}
remote_path=${BASH_REMATCH[3]}
[[ $remote_path != *"'"* ]] || {
  echo "the path has a single quote, which lftp's command line here cannot carry: $remote_path" >&2
  exit 1
}
block_mb=${NAS_PGET_BLOCK_MB:-200}
[[ $block_mb =~ ^[1-9][0-9]*$ ]] || {
  echo "NAS_PGET_BLOCK_MB must be a whole number of MiB, got: $block_mb" >&2
  exit 1
}
command -v lftp >/dev/null || {
  echo "lftp not found: it is in nix/flake.nix, see README.md for the nix profile setup" >&2
  exit 1
}
[ -d "$dest_dir" ] || {
  echo "dest_dir does not exist: $dest_dir" >&2
  exit 1
}

# shellcheck source=scripts/lib/event_log.sh
. "$(dirname "$0")/lib/event_log.sh"
event_log_start nas_pget

mib=1048576
block=$((block_mb * mib))
tail_bytes=$((16 * mib))
pieces=16

# pget writes to the current directory under the remote file's name.
cd "$dest_dir"
name=${remote_path##*/}
status=$name.lftp-pget-status
state=$name.nas-pget-next

# ControlMaster must be off: with one set for the host in ~/.ssh/local_config,
# every piece would ride a single multiplexed TCP connection and the whole
# point is lost.
# BatchMode makes a missing key fail immediately instead of hanging on a
# password prompt.
connect_program='ssh -a -x -o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4'

# nas_lftp <command>: run one lftp command against the NAS.
# lftp -e separates commands with ';' -- newlines are not separators.
# max-retries 0 means unlimited: a dying connection reconnects until its
# piece is done.
nas_lftp() {
  lftp -e "set sftp:connect-program '$connect_program'; set cmd:fail-exit yes; set net:connection-limit 0; set net:timeout 120; set net:max-retries 0; set net:reconnect-interval-base 5; set net:reconnect-interval-max 30; $1; quit" "$nas_url"
}

save_state() {
  printf '%s %s\n' "$size" "$1" >"$state.tmp"
  mv "$state.tmp" "$state"
}

# block_end <start>: where the block starting there ends. A last block under
# an eighth of a block joins the one before it.
block_end() {
  local end=$(($1 + block))
  [ $((tail_start - end)) -ge $((block / 8)) ] || end=$tail_start
  echo "$end"
}

# write_status <start> <end>: point pget at that range, as $pieces pieces.
write_status() {
  local start=$1 len=$(($2 - $1)) i
  {
    echo "size=$size"
    for ((i = 0; i < pieces; i++)); do
      echo "$i.pos=$((start + len * i / pieces))"
      echo "$i.limit=$((start + len * (i + 1) / pieces))"
    done
  } >"$status.tmp"
  mv "$status.tmp" "$status"
}

# status_is_for <start> <end>: whether lftp's status file is a whole one for
# this file with every piece inside that range. lftp rewrites it in place, so
# one killed at that moment leaves it empty.
status_is_for() {
  awk -F= -v size="$size" -v start="$1" -v end="$2" '
    NR == 1 { if ($0 != "size=" size) bad = 1; next }
    /^[0-9]+\.(pos|limit)=[0-9]+$/ { if ($2 + 0 < start || $2 + 0 > end) bad = 1; next }
    { bad = 1 }
    END { exit bad || NR < 3 }' "$status"
}

listing=$(nas_lftp "cls -1 -s --block-size=1 '$remote_path'") \
  || die "lftp could not list $remote_path on the NAS"
read -r size _ <<<"$listing"
[[ $size =~ ^[0-9]+$ ]] || die "no size in lftp's listing of $remote_path: $listing"
[ "$size" -ge "$pieces" ] || die "$remote_path is $size bytes, too small to cut into $pieces pieces: copy it with scp"

if [ -e "$state" ]; then
  read -r started_size next <"$state" || die "$PWD/$state is empty: delete it, $name and $status to start again"
  [ "$started_size" = "$size" ] \
    || die "$remote_path is $size bytes on the NAS and was $started_size when this download began: delete $name, $state and $status in $PWD to start again"
  [ "$next" = tail ] || [ -e "$name" ] \
    || die "$state is in $PWD without $name: delete it and $status to start again"
elif [ -e "$name" ]; then
  [ ! -e "$status" ] \
    || die "$name in $PWD is a download this script did not begin ($status without $state): finish it with lftp, or delete both to start again"
  local_size=$(($(wc -c <"$name")))
  [ "$local_size" -eq "$size" ] \
    || die "$name in $PWD has $local_size bytes and the NAS file $size: move it away to download"
  log "already complete: $PWD/$name, $size bytes"
  exit 0
else
  save_state tail
fi
# A status file whose download is gone would have pget skip what it lists as
# fetched.
[ -e "$name" ] || rm -f "$status"

tail_start=$((size - tail_bytes))
[ "$tail_start" -ge $((block / 8)) ] || tail_start=0

log "$remote_path, $((size / mib)) MiB -> $PWD/$name"
while :; do
  read -r _ next <"$state" || die "$PWD/$state is empty"
  if [ "$next" = tail ]; then
    start=$tail_start end=$size
  else
    [[ $next =~ ^[0-9]+$ ]] || die "$PWD/$state names no block: $next"
    start=$next
    [ "$start" -lt "$tail_start" ] || break
    end=$(block_end "$start")
  fi

  if [ -e "$status" ] && status_is_for "$start" "$end"; then
    log "block [$start,$end): resuming"
  else
    write_status "$start" "$end"
    log "block [$start,$end): $(((end - start) / mib)) MiB"
  fi
  nas_lftp "pget -n $pieces -c '$remote_path'" \
    || die "lftp failed in block [$start,$end): run the same command again to carry on"
  [ ! -e "$status" ] \
    || die "lftp left block [$start,$end) unfinished ($status remains): run the same command again to carry on"

  if [ "$next" = tail ]; then
    save_state 0
    log "end of the file is here"
  else
    save_state "$end"
    [ "$end" -lt "$tail_start" ] || end=$size
    log "playable from the start up to $((end / mib)) of $((size / mib)) MiB ($((end * 100 / size))%)"
  fi
done
rm "$state"
log "done: $PWD/$name, $size bytes"

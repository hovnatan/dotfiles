#!/usr/bin/env bash
#
# nas_pget.sh -- pull one large file from the home NAS over sftp, fast, on a
# lossy long-haul path.
#
#   NAS_SFTP_URL='sftp://user:dummy@host:port' \
#     ~/.dotfiles/scripts/nas_pget.sh 'share/path/to/file' [dest_dir]
#
# Why this exists (measured 2026-09-04, Armenia -> US east coast, 150 ms RTT):
# the return path drops ~0.5% of packets at a congested carrier handoff, which
# caps any single TCP flow at ~0.4 MB/s. Throughput therefore comes from flow
# count. lftp's pget splits the file into N segments, pulls each over its own
# ssh connection (~3 MB/s with 16), and records every segment's offset in a
# `<file>.lftp-pget-status` file next to the download, so a segment whose
# connection dies resumes where it stopped. rclone's multi-thread copy gets the
# same rate but a mid-chunk connection death is fatal for the whole file, and
# connections on this path die every 10-30 minutes.
#
#   16 x [ssh -> sftp-server]  ==lossy WAN==>  lftp pget  -->  <dest>/<name>
#                                                        `->  <name>.lftp-pget-status
#
# The URL lives in an env var, not here: this repo is public and the address,
# port and user name of a home NAS do not belong in it. The "dummy" password is
# never used (ssh authenticates with the key) but lftp falls back to an
# anonymous login as the local user without one.
#
# Requires: lftp (brew install lftp), key-based ssh auth to the NAS.

set -euo pipefail

usage() {
  echo "usage: NAS_SFTP_URL='sftp://user:dummy@host:port' $0 <remote_path> [dest_dir]" >&2
  exit 2
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
remote_path=$1
dest_dir=${2:-.}
: "${NAS_SFTP_URL:?set NAS_SFTP_URL, e.g. sftp://user:dummy@host:port}"
command -v lftp >/dev/null || { echo "lftp not found: brew install lftp" >&2; exit 1; }
[ -d "$dest_dir" ] || { echo "dest_dir does not exist: $dest_dir" >&2; exit 1; }

# ControlMaster must be off: with it, every segment would ride the one
# multiplexed TCP connection from ~/.ssh/config and the whole point is lost.
# BatchMode makes a missing key fail immediately instead of hanging on a
# password prompt.
connect_program='ssh -a -x -o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4'

# lftp -e separates commands with ';' -- newlines are not separators.
# max-retries 0 means unlimited: a dying segment reconnects until it finishes.
# pget writes to the current directory under the remote file's name, hence
# the cd; -c resumes from the status file if a previous run was interrupted.
cd "$dest_dir"
exec lftp -e "set sftp:connect-program '$connect_program'; set net:connection-limit 0; set net:timeout 120; set net:max-retries 0; set net:reconnect-interval-base 5; set net:reconnect-interval-max 30; pget -n 16 -c '$remote_path'; quit" "$NAS_SFTP_URL"

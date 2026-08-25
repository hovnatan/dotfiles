#!/bin/sh
#
# ssh_folder_sync.sh -- mirror a pair of exchange folders between this machine
# and a remote host, for as long as an SSH connection to that host is open.
#
#   local  <local-root>/out/  ->  remote <remote-root>/in/
#   remote <remote-root>/out/ ->  local  <local-root>/in/
#
# Put a file in out/, collect it from the other machine's in/.  Handy for
# passing screenshots and tarballs around; not meant for a source tree, since
# every pass walks both trees.
#
# Each direction is a strict ONE-WAY MIRROR, and that is the point: it makes
# deletion work.  Drop a file from your out/ and it is gone from their in/ on
# the next pass.  Two-way sync of a single shared folder cannot do that with
# plain rsync -- rsync keeps no history, so it cannot tell "deleted here" from
# "created there", and the file just comes back from the other side.  Doing it
# properly needs unison or mutagen and their state snapshots.
#
# The flip side of a mirror: in/ is not yours to write to.  It is kept
# identical to the other side's out/, so anything you create there is removed
# on the next pass.  Move it to your out/ if you want to send it back.
#
# Wire it up from ssh_config -- keep the host-specific paths there, so this
# script stays generic:
#
#     Host somehost
#         PermitLocalCommand yes
#         LocalCommand ~/.dotfiles/scripts/ssh_folder_sync.sh start %n \
#             /Users/you/exchange workspace/exchange
#
# LocalCommand runs only for the connection that becomes the ControlMaster, so
# one loop is started per real connection, not per multiplexed session.
#
# Usage:
#   ssh_folder_sync.sh start  <host> <local-root> <remote-root>   detach and run
#   ssh_folder_sync.sh run    <host> <local-root> <remote-root>   run in foreground
#   ssh_folder_sync.sh stop   <host>
#   ssh_folder_sync.sh status <host>
#
# <remote-root> is interpreted by the remote shell, so a relative path is
# relative to the remote home directory.

set -u

INTERVAL=3
STATE_DIR="$HOME/.local/state/ssh-folder-sync"
LOG_MAX_BYTES=1048576

# Apple ships openrsync as /usr/bin/rsync, which lacks the flags used here, so
# prefer a real rsync 3.x if one is installed.
for candidate in /opt/homebrew/bin/rsync /usr/local/bin/rsync; do
    [ -x "$candidate" ] && { RSYNC="$candidate"; break; }
done
: "${RSYNC:=$(command -v rsync 2>/dev/null)}"

case "$0" in
    /*) SELF=$0 ;;
    *)  SELF="$PWD/$0" ;;
esac

usage() {
    echo "usage: $SELF {start|run} <host> <local-root> <remote-root>" >&2
    echo "       $SELF {stop|status} <host>" >&2
    exit 2
}

ACTION="${1:-}"
HOST="${2:-}"
[ -n "$ACTION" ] && [ -n "$HOST" ] || usage

mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/$HOST.log"
SOCK="$STATE_DIR/cm-$HOST.sock"

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >>"$LOG"; }
connected() { ssh -O check "$HOST" >/dev/null 2>&1; }
# Matches only this host's loop, so several hosts can each have one.
loop_pids() { pgrep -f "ssh_folder_sync.sh run $HOST " 2>/dev/null; }

case "$ACTION" in
    stop)
        if loop_pids | xargs kill 2>/dev/null; then echo "$HOST: sync loop stopped"
        else echo "$HOST: sync loop not running"; fi
        ssh -O exit -o ControlPath="$SOCK" "$HOST" >/dev/null 2>&1
        exit 0 ;;
    status)
        if [ -n "$(loop_pids)" ]; then echo "$HOST: sync loop running (every ${INTERVAL}s)"
        else echo "$HOST: sync loop not running"; fi
        exit 0 ;;
    start|run) : ;;
    *) usage ;;
esac

LOCAL_ROOT="${3:-}"
REMOTE_ROOT="${4:-}"
[ -n "$LOCAL_ROOT" ] && [ -n "$REMOTE_ROOT" ] || usage
[ -n "${RSYNC:-}" ] || { echo "$SELF: no rsync found" >&2; exit 1; }

if [ "$ACTION" = start ]; then
    # LocalCommand blocks the SSH client until it returns, and the client does
    # not answer its multiplexing socket while it waits -- which the loop needs
    # in order to see the connection.  So detach hard before doing any SSH.
    # setsid puts the loop in its own session, so a signal aimed at the
    # terminal's process group cannot take it down; nohup alone covers only
    # SIGHUP, and macOS has no setsid(1), hence perl.
    if [ -x /usr/bin/perl ]; then
        ( nohup /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \
            -- "$SELF" run "$HOST" "$LOCAL_ROOT" "$REMOTE_ROOT" >/dev/null 2>&1 & ) &
    else
        ( nohup "$SELF" run "$HOST" "$LOCAL_ROOT" "$REMOTE_ROOT" >/dev/null 2>&1 & ) &
    fi
    exit 0
fi

# One loop per host, however many times LocalCommand fires.
if loop_pids | grep -qv "^$$\$"; then exit 0; fi

if [ -f "$LOG" ] && [ "$(wc -c <"$LOG")" -gt "$LOG_MAX_BYTES" ]; then
    tail -c 262144 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# A private multiplexed connection, so a pass costs no handshake.  It
# deliberately does not share your session's connection: reusing that one would
# keep resetting its ControlPersist timer, and the loop would hold your
# connection open forever instead of noticing you had logged out.
SSH_T="ssh -o ControlPath=$SOCK -o ControlMaster=auto -o ControlPersist=30 -o PermitLocalCommand=no -o ClearAllForwardings=yes -o BatchMode=yes"
FILTER="--exclude=.DS_Store --exclude=.rsync-partial --partial-dir=.rsync-partial"

mkdir -p "$LOCAL_ROOT/out" "$LOCAL_ROOT/in"

# A socket left behind by a loop that was killed makes ssh warn and fall back
# to unmultiplexed connections, which then shows up as noise in rsync stderr.
if [ -S "$SOCK" ] && ! ssh -O check -o ControlPath="$SOCK" "$HOST" >/dev/null 2>&1; then
    rm -f "$SOCK"
fi

# The SSH client does not answer its multiplexing socket while LocalCommand is
# still running, so give the connection a moment before declaring it absent.
n=0
while ! connected; do
    n=$((n + 1))
    [ $n -ge 15 ] && exit 0
    sleep 1
done

$SSH_T "$HOST" "mkdir -p '$REMOTE_ROOT/in' '$REMOTE_ROOT/out'" >/dev/null 2>&1
log "loop started (every ${INTERVAL}s): $LOCAL_ROOT/out -> $HOST:$REMOTE_ROOT/in, back into $LOCAL_ROOT/in"
while connected; do
    # --delete is what makes deletions propagate.  A missing source directory
    # makes rsync fail rather than empty the far side, which is the safe way
    # round for a mirror.
    sent=$($RSYNC -a --delete -i $FILTER -e "$SSH_T" \
             "$LOCAL_ROOT/out/" "$HOST:$REMOTE_ROOT/in/" 2>&1)
    [ -n "$sent" ] && log "out -> $HOST: $(printf '%s' "$sent" | tr '\n' ' ')"
    recv=$($RSYNC -a --delete -i $FILTER -e "$SSH_T" \
             "$HOST:$REMOTE_ROOT/out/" "$LOCAL_ROOT/in/" 2>&1)
    [ -n "$recv" ] && log "$HOST -> in: $(printf '%s' "$recv" | tr '\n' ' ')"
    sleep "$INTERVAL"
done
log "connection to $HOST closed; loop exiting"
ssh -O exit -o ControlPath="$SOCK" "$HOST" >/dev/null 2>&1

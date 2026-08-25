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
# one loop is started per real connection, not per multiplexed session.  That
# makes connection multiplexing a REQUIREMENT rather than a tuning choice:
# the loop watches your session's mux socket to know when you have logged out,
# so ControlMaster/ControlPath must be set for the host (typically in a
# Host * block).  Without them the loop logs a line and exits.
#
# Usage:
#   ssh_folder_sync.sh start  <host> <local-root> <remote-root>   detach and run
#   ssh_folder_sync.sh run    <host> <local-root> <remote-root>   run in foreground
#   ssh_folder_sync.sh stop   <host>
#   ssh_folder_sync.sh status <host>
#
# <remote-root> is interpreted by the remote shell, so a relative path is
# relative to the remote home directory.  Set RSYNC=/path/to/rsync to override
# binary discovery.

set -u

INTERVAL=3              # seconds between passes
CONNECT_WAIT=15         # seconds to wait for the ssh connection before giving up
LOG_KEEP_BYTES=262144   # log is trimmed back to this
TRIM_EVERY=200          # passes between trims (~10 min at INTERVAL=3)

STATE_DIR="$HOME/.local/state/ssh-folder-sync"
# The control socket is volatile, and must stay SHORT: macOS caps unix socket
# paths at 104 bytes, which $STATE_DIR (106 for a 37-char host alias) and a
# macOS $TMPDIR (110) both blow.  A runtime dir is shorter and reboot-clean.
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/ssh-folder-sync"

usage() {
    echo "usage: ${0##*/} {start|run} <host> <local-root> <remote-root>" >&2
    echo "       ${0##*/} {stop|status} <host>" >&2
    exit 2
}

ACTION="${1:-}"; HOST="${2:-}"; LOCAL_ROOT="${3:-}"; REMOTE_ROOT="${4:-}"
case "$ACTION" in
    start|run)   [ -n "$HOST" ] && [ -n "$LOCAL_ROOT" ] && [ -n "$REMOTE_ROOT" ] || usage ;;
    stop|status) [ -n "$HOST" ] || usage ;;
    *)           usage ;;
esac

LOG="$STATE_DIR/$HOST.log"
SOCK="$RUN_DIR/cm-$HOST.sock"

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >>"$LOG"; }
# Liveness: does your session's master still exist?  This is a stat, NOT a
# connection, and that distinction is the whole point.  "ssh -O check" would
# be the obvious test, but connecting to a master cancels its ControlPersist
# countdown -- polling it every few seconds pins open the very connection we
# are trying to watch, so the loop would outlive your session forever.  ssh
# unlinks the socket when the master exits (timeout, -O exit, or dropped
# link), so its absence is the signal.  The one case a stat cannot see is a
# socket orphaned by a SIGKILLed master; then the loop keeps running, which
# is no worse than the behaviour this replaced.
connected() { [ -S "$SESSION_SOCK" ]; }
# The loop's own private master (see SSH_T), which is a different socket.
ctl() { ssh -O "$1" -o ControlPath="$SOCK" "$HOST" >/dev/null 2>&1; }
# Finds this host's loop by its argv, so several hosts can each have one.  The
# literal "run" is the subcommand below: rename that and this stops matching.
# $HOST lands in a regex unescaped, which is fine for ordinary aliases.
loop_pids() { pgrep -f "ssh_folder_sync.sh run $HOST " 2>/dev/null; }

case "$ACTION" in
    stop)
        pids=$(loop_pids)
        if [ -n "$pids" ]; then kill $pids 2>/dev/null; echo "$HOST: sync loop stopped"
        else echo "$HOST: sync loop not running"; fi
        ctl exit
        exit 0 ;;
    status)
        if [ -n "$(loop_pids)" ]; then echo "$HOST: sync loop running (every ${INTERVAL}s), log: $LOG"
        else echo "$HOST: sync loop not running"; fi
        exit 0 ;;
esac

# rsync has to be a real rsync 3.x.  Apple ships openrsync as /usr/bin/rsync
# and it has neither -i nor --partial-dir, so a bare PATH lookup can hand us a
# binary that fails on every single pass.  Probed here, before the fork, so
# the complaint reaches your terminal instead of the child's /dev/null.
if [ -z "${RSYNC:-}" ]; then
    for candidate in /opt/homebrew/bin/rsync /usr/local/bin/rsync /opt/local/bin/rsync rsync; do
        RSYNC=$(command -v "$candidate" 2>/dev/null) && break
    done
fi
[ -n "$RSYNC" ] && [ -x "$RSYNC" ] || {
    echo "${0##*/}: no usable rsync at '${RSYNC:-}'; set RSYNC=/path/to/rsync" >&2; exit 1; }
case "$("$RSYNC" --version 2>/dev/null | head -1)" in
    *"protocol version"*[3-9][0-9]*) : ;;
    *) echo "${0##*/}: $RSYNC is not a usable rsync 3.x (openrsync lacks -i and --partial-dir); set RSYNC=/path/to/rsync" >&2
       exit 1 ;;
esac

if [ "$ACTION" = start ]; then
    case "$0" in
        /*) SELF=$0 ;;
        *)  SELF="$PWD/$0" ;;
    esac
    # LocalCommand blocks the SSH client until it returns, and the client does
    # not answer its multiplexing socket while it waits -- which the loop needs
    # in order to see the connection.  So detach hard before doing any SSH.
    #
    # The loop has to survive SIGHUP *and* a signal aimed at the terminal's
    # process group, which means a session of its own.  setsid(1) is the native
    # way; macOS does not ship it, so fall back to perl's POSIX::setsid.  The
    # wrapping ( ... & ) & backgrounds twice so the child is not a process
    # group leader, since setsid() fails with EPERM if it is.
    if command -v setsid >/dev/null 2>&1; then
        ( setsid "$SELF" run "$HOST" "$LOCAL_ROOT" "$REMOTE_ROOT" >/dev/null 2>&1 & ) &
    elif [ -x /usr/bin/perl ]; then
        ( /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \
            -- "$SELF" run "$HOST" "$LOCAL_ROOT" "$REMOTE_ROOT" >/dev/null 2>&1 & ) &
    else
        echo "${0##*/}: need setsid(1) or /usr/bin/perl to detach" >&2
        exit 1
    fi
    exit 0
fi

# One loop per host, however many times LocalCommand fires.
loop_pids | grep -qvx "$$" && exit 0

# ssh -G expands the %r/%h/%p tokens, so this is the real socket path.  No
# ControlPath means no way to tell when you have logged out, and the loop has
# no business running.
SESSION_SOCK=$(ssh -G "$HOST" 2>/dev/null | awk '$1 == "controlpath" { print $2; exit }')

mkdir -p "$STATE_DIR" "$RUN_DIR" "$LOCAL_ROOT/out" "$LOCAL_ROOT/in" || exit 1

# Trimmed periodically, not just at startup: a wrong remote path makes both
# rsyncs write to stderr every pass, which is ~0.5 MB/hour of log for exactly
# as long as the session lasts.
trim_log() {
    [ -f "$LOG" ] || return 0
    [ "$(wc -c <"$LOG")" -gt "$LOG_KEEP_BYTES" ] || return 0
    tail -c "$LOG_KEEP_BYTES" "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}
trim_log

# A private multiplexed connection, so a pass costs no handshake.  It must not
# share your session's connection: rsync traffic over that one would keep
# resetting its ControlPersist timer and pin it open.  See connected() for the
# other half of the same hazard.
SSH_T="ssh -o ControlPath=$SOCK -o ControlMaster=auto -o ControlPersist=30 -o PermitLocalCommand=no -o ClearAllForwardings=yes -o BatchMode=yes"
FILTER="--exclude=.DS_Store --exclude=.rsync-partial --partial-dir=.rsync-partial"

# mirror <label> <src> <dst> -- --delete is what makes deletions propagate.  A
# missing source makes rsync fail rather than empty the far side, which is the
# safe way round for a mirror.
mirror() {
    _out=$($RSYNC -a --delete -i $FILTER -e "$SSH_T" "$2" "$3" 2>&1)
    [ -n "$_out" ] && log "$1: $(printf '%s' "$_out" | tr '\n' ' ')"
    return 0
}

# A socket left behind by a killed loop makes ssh warn and fall back to
# unmultiplexed connections, which then shows up as noise in rsync stderr.
[ -S "$SOCK" ] && ! ctl check && rm -f "$SOCK"

# The master binds its socket before running LocalCommand, so this normally
# passes on the first try; the wait only covers an unusually slow setup.
if [ -z "$SESSION_SOCK" ] || [ "$SESSION_SOCK" = none ]; then
    log "$HOST has no ControlPath; cannot track the session, not starting"
    exit 0
fi

n=0
while ! connected; do
    n=$((n + 1))
    if [ "$n" -ge "$CONNECT_WAIT" ]; then
        log "no ssh master socket for $HOST after ${CONNECT_WAIT}s; not starting (is ControlMaster/ControlPath set for this host?)"
        exit 0
    fi
    sleep 1
done

$SSH_T "$HOST" "mkdir -p '$REMOTE_ROOT/in' '$REMOTE_ROOT/out'" >/dev/null 2>&1
log "loop started (every ${INTERVAL}s): $LOCAL_ROOT/out -> $HOST:$REMOTE_ROOT/in, back into $LOCAL_ROOT/in"

passes=0
while connected; do
    mirror "out -> $HOST" "$LOCAL_ROOT/out/"        "$HOST:$REMOTE_ROOT/in/"
    mirror "$HOST -> in"  "$HOST:$REMOTE_ROOT/out/" "$LOCAL_ROOT/in/"
    passes=$((passes + 1))
    [ $((passes % TRIM_EVERY)) -eq 0 ] && trim_log
    sleep "$INTERVAL"
done
log "connection to $HOST closed; loop exiting"
ctl exit

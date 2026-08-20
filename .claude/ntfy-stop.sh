#!/usr/bin/env bash
# Claude Code Stop hook: push to ntfy.sh when a session finishes a turn and
# nobody comes to look within DEBOUNCE_SECONDS (default 10 minutes).
#
# Hook mode (no args): must return within the hook timeout, so it checks
# whether anyone is looking right now and otherwise forks the waiter,
# detached, and exits. Waiter mode (--wait): poll the tmux session's
# focus for DEBOUNCE_SECONDS. A client of this session reporting fresh
# focus at any poll cancels the push -- the user saw the result. Growth
# of the conversation transcript re-arms the window: every form of
# engagement lands there -- local typing, Remote Control input from the
# phone, a superseding turn -- so it is the one signal that dismisses a
# pending push regardless of channel. Only a full window of quiet sends
# the push. This channel is a deliberate, independent backup to Claude
# Code's native mobile push: it gates on tmux's own client focus rather
# than claude's internal presence state, and adds debounce-with-cancel
# semantics the native push lacks.
#
# The session is identified by ID (third $TMUX field, stable across
# renames for the server's lifetime; same idiom as notify-stop.sh's
# guard). Unlike the bell's pure focus check, the cancel here also
# requires the focus to be FRESH (see watched()) -- a bell into a locked
# screen is harmless, a suppressed push is not.  The human-readable name
# is resolved only at push time, for the title, whose <hostname>-<name>
# form matches the conversation/peer naming claude_tmux_run.sh owns.
#
# The topic is read from ~/.config/claude-ntfy/topic, which stays OUTSIDE
# the dotfiles repo on purpose: an ntfy.sh topic name is a capability --
# anyone who knows it can subscribe. No topic file = do nothing, so this
# hook is a no-op on machines where it is not set up.
#
# Portability: runs on stock macOS too, which lacks flock(1) and
# setsid(1) (both util-linux), has no /run, and ships bash 3.2 and no jq
# -- hence the mkdir lock, the command -v setsid-else-nohup fork, the
# TMPDIR fallback, and sed for the hook JSON. Lock dirs live on volatile
# per-user storage on both OSes, so a reboot clears them; a waiter that
# died leaves a lock whose pid is dead, which the next waiter overwrites.
set -u

DEBOUNCE_SECONDS="${CLAUDE_NTFY_DEBOUNCE_SECONDS:-600}"
POLL_SECONDS=5
STALE_SECONDS="${CLAUDE_NTFY_STALE_SECONDS:-1800}"
TOPIC_FILE="$HOME/.config/claude-ntfy/topic"
NTFY_URL="${CLAUDE_NTFY_URL:-https://ntfy.sh}"
RUN_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"   # Linux tmpfs, else macOS per-user tmp

# watched <socket> <session-id>: status 0 if a client of the session is
# focused AND produced input within STALE_SECONDS, 1 if not, 2 if the
# session is gone. The freshness bound exists because a locked/asleep Mac
# freezes the outer terminal without ever sending a focus-out, leaving
# the flag stuck at "focused" -- but a frozen terminal also sends no
# input, so activity ages past the bound and pushes resume (a Stop within
# the first STALE_SECONDS of the lock stays suppressed; that is the
# heuristic's floor). Coming back refreshes activity with no typing
# needed: the focus-in event itself counts as client input (verified), as
# do mouse scrolls. tmux evaluates the whole predicate itself via the -f
# filter; the shell only tests whether any client matched.
watched() {
  local now hit
  now=${EPOCHSECONDS:-$(date +%s)}   # builtin on bash 5+; forks on macOS 3.2
  hit=$(tmux -S "$1" list-clients -t "\$$2" \
    -f "#{&&:#{m:*focused*,#{client_flags}},#{e|<:$((now - STALE_SECONDS)),#{client_activity}}}" \
    -F w 2>/dev/null) || return 2
  [ -n "$hit" ]
}

if [ "${1:-}" = --wait ]; then
  socket="$2" sid="$3" topic="$4" transcript="${5:-}"
  # One waiter per (socket, session): a Stop landing while one is pending
  # is the same "come look" request, so it is coalesced. mkdir is the
  # portable atomic lock; the recorded pid lets the next waiter claim a
  # crashed waiter's lock instead of wedging the session until reboot.
  # The pid file does double duty: its content is the liveness claim, its
  # mtime is the current window's start (the re-arm below refreshes it).
  lock="$RUN_DIR/claude-ntfy/${socket##*/}-$sid.lock"
  mkdir -p "${lock%/*}"
  if ! mkdir "$lock" 2>/dev/null; then
    kill -0 "$(cat "$lock/pid" 2>/dev/null)" 2>/dev/null && exit 0  # waiter pending
  fi
  echo $$ > "$lock/pid"
  trap 'rm -rf "$lock"' EXIT

  end=$((SECONDS + DEBOUNCE_SECONDS))
  while [ "$SECONDS" -lt "$end" ]; do
    # Watched (0) -> the user saw it; gone (2) -> nothing to report on.
    watched "$socket" "$sid"
    case $? in 0|2) exit 0 ;; esac
    # Transcript grew since this window started: the user engaged (from
    # any channel) or a new turn superseded the one we are advertising.
    # Restart the window; the push then fires only after a full
    # DEBOUNCE_SECONDS of quiet.
    if [ -n "$transcript" ] && [ "$transcript" -nt "$lock/pid" ]; then
      echo $$ > "$lock/pid"
      end=$((SECONDS + DEBOUNCE_SECONDS))
    fi
    sleep "$POLL_SECONDS"
  done

  # Resolve the name only now, once per push; gone since the last poll
  # means there is nothing left to come look at.
  session=$(tmux -S "$socket" display-message -p -t "\$$sid" '#{session_name}' 2>/dev/null)
  [ -n "$session" ] || exit 0
  curl -sf --max-time 10 \
    -H "Title: CC: $(hostname)-$session" \
    -H "Tags: speech_balloon" \
    -d "finished a turn ${DEBOUNCE_SECONDS}s ago and is still unwatched" \
    "$NTFY_URL/$topic" > /dev/null
  exit 0
fi

# --- hook mode: cheap checks, then fork the waiter and get out of the way ---
[ -n "${TMUX:-}" ] || exit 0            # not a tmux-hosted session
IFS= read -r topic < "$TOPIC_FILE" 2>/dev/null
[ -n "${topic:-}" ] || exit 0
socket=${TMUX%%,*} sid=${TMUX##*,}      # $TMUX = socket-path,server-pid,session-id
watched "$socket" "$sid" && exit 0      # user is looking right now -- no waiter
# The hook JSON on stdin carries the conversation transcript's path; the
# waiter watches its mtime (see loop). sed, not jq: stock macOS has no jq.
transcript=$(sed -n 's/.*"transcript_path":"\([^"]*\)".*/\1/p' 2>/dev/null)

# setsid fully detaches (survives signals to claude's process group);
# stock macOS has no setsid, so fall back to nohup there.
runner=$(command -v setsid || echo nohup)
"$runner" "$0" --wait "$socket" "$sid" "$topic" "$transcript" \
  < /dev/null > /dev/null 2>&1 &
exit 0

#!/usr/bin/env bash
# Claude Code Stop hook: push to ntfy.sh when a session finishes a turn and
# nobody comes to look within DEBOUNCE_SECONDS (default 10 minutes).
#
# Hook mode (no args): must return within the hook timeout, so it checks
# whether anyone is looking right now and otherwise forks the waiter,
# detached, and exits. Waiter mode (--wait): poll the tmux session's focus
# for DEBOUNCE_SECONDS; a client of this session reporting "focused" at
# any poll cancels the push -- the user saw the result themselves. Only if
# the whole window passes unwatched does the push go out. This channel is
# a deliberate, independent backup to Claude Code's native mobile push: it
# gates on tmux's own client focus rather than claude's internal presence
# state, and adds debounce-with-cancel semantics the native push lacks.
#
# The session is identified by ID (third $TMUX field, stable across
# renames for the server's lifetime; same idiom as notify-stop.sh's guard
# -- keep the two predicates in sync). The human-readable name is resolved
# only at push time, for the title, whose <hostname>-<name> form matches
# the conversation/peer naming claude_tmux_run.sh owns.
#
# The topic is read from ~/.config/claude-ntfy/topic, which stays OUTSIDE
# the dotfiles repo on purpose: an ntfy.sh topic name is a capability --
# anyone who knows it can subscribe. No topic file = do nothing, so this
# hook is a no-op on machines where it is not set up.
#
# Portability: runs on stock macOS too, which lacks flock(1) and
# setsid(1) (both util-linux) and has no /run -- hence the mkdir lock,
# the command -v setsid-else-nohup fork, and the TMPDIR fallback. Lock
# dirs live on volatile per-user storage on both OSes, so a reboot clears
# them; a waiter that died leaves a lock whose pid is dead, which the
# next waiter overwrites.
set -u

DEBOUNCE_SECONDS="${CLAUDE_NTFY_DEBOUNCE_SECONDS:-600}"
POLL_SECONDS=5
TOPIC_FILE="$HOME/.config/claude-ntfy/topic"
NTFY_URL="${CLAUDE_NTFY_URL:-https://ntfy.sh}"
RUN_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"   # Linux tmpfs, else macOS per-user tmp

client_flags() { # <socket> <session-id>: print client flags; fail if session gone
  tmux -S "$1" list-clients -t "\$$2" -F '#{client_flags}' 2>/dev/null
}

if [ "${1:-}" = --wait ]; then
  socket="$2" sid="$3" topic="$4"
  # One waiter per (socket, session): a Stop landing while one is pending
  # is the same "come look" request, so it is coalesced. mkdir is the
  # portable atomic lock; the recorded pid lets the next waiter claim a
  # crashed waiter's lock instead of wedging the session until reboot.
  lock="$RUN_DIR/claude-ntfy/${socket##*/}-$sid.lock"
  mkdir -p "${lock%/*}"
  if ! mkdir "$lock" 2>/dev/null; then
    kill -0 "$(cat "$lock/pid" 2>/dev/null)" 2>/dev/null && exit 0  # waiter pending
  fi
  echo $$ > "$lock/pid"
  trap 'rm -rf "$lock"' EXIT

  end=$((SECONDS + DEBOUNCE_SECONDS))
  while [ "$SECONDS" -lt "$end" ]; do
    # Session gone (killed) -> nothing to report on; focused -> user saw it.
    flags=$(client_flags "$socket" "$sid") || exit 0
    case $flags in *focused*) exit 0 ;; esac
    sleep "$POLL_SECONDS"
  done

  # Resolve the name only now, once per push; gone since the last poll
  # means there is nothing left to come look at.
  session=$(tmux -S "$socket" display-message -p -t "\$$sid" '#{session_name}' 2>/dev/null)
  [ -n "$session" ] || exit 0
  curl -sf --max-time 10 \
    -H "Title: Claude Code: $(hostname)-$session" \
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
case $(client_flags "$socket" "$sid") in
*focused*) exit 0 ;;                    # user is looking right now -- no waiter
esac

# setsid fully detaches (survives signals to claude's process group);
# stock macOS has no setsid, so fall back to nohup there.
runner=$(command -v setsid || echo nohup)
"$runner" "$0" --wait "$socket" "$sid" "$topic" < /dev/null > /dev/null 2>&1 &
exit 0

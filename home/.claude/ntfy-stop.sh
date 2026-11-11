#!/usr/bin/env bash
# Claude Code Stop hook: push to ntfy.sh when a session finishes a turn and
# nobody comes to look within DEBOUNCE_SECONDS (default 10 minutes).
#
# Hook mode (no args): must return within the hook timeout, so it checks
# whether anyone is looking right now and otherwise forks the waiter,
# detached, and exits. Waiter mode (--wait): poll the tmux session's
# focus for DEBOUNCE_SECONDS. A client of this session reporting fresh
# focus at any poll, with claude's pane on screen, cancels the push -- the
# user saw the result. So does
# a new message from the user, whatever the channel: --cancel, fired by
# the UserPromptSubmit hook, kills the pending waiter. Transcript growth
# re-arms the window, so a turn superseding the advertised one gets its
# own full watch. Only a full window of quiet sends the push. This
# channel is a deliberate, independent backup to Claude
# Code's native mobile push: it gates on tmux's own client focus rather
# than claude's internal presence state, and adds debounce-with-cancel
# semantics the native push lacks.
#
# The session is identified by ID (third $TMUX field, stable across
# renames for the server's lifetime), and claude's pane by $TMUX_PANE: a
# session can hold more windows than claude's (nvim, a shell), and a client
# typing in one of those has not seen the turn. On screen means the
# session's current window is the pane's, and that window is not zoomed
# onto another of its panes. The current window is per session in tmux, so
# every client of a session agrees on it. The pane's window is looked up at
# every poll, as break-pane / join-pane move a pane between windows and
# move-window / join-pane between sessions; a client counts by the window
# it shows, whatever session it is attached to:
#
#   session $3 (current window @2)
#     @1  claude %4        <- the turn finished here
#     @2  nvim             <- pts/1, focused: not watching %4 -> push
#
# The cancel requires the focus to be FRESH, not just present (see
# watched()): a client left focused on a locked screen must not suppress
# the push. The human-readable name
# is resolved in hook mode for the log lines, and again at push time for
# the title (a /rename may have labeled the session meanwhile), in the
# form <hostname>/<name>.
#
# The topic is read from ~/.config/claude-ntfy/topic, which stays OUTSIDE
# the dotfiles repo on purpose: an ntfy.sh topic name is a capability --
# anyone who knows it can subscribe. No topic file = do nothing, so this
# hook is a no-op on machines where it is not set up.
#
# Every decision is logged, one line each, so a push that did or did not
# arrive can be explained afterwards. The hook, the waiter and the cancel
# are three processes writing one story, so they share a log: a directory
# per UTC day (scripts/lib/event_log.sh, event_log_daily), not one per run.
#   tail -f ~/.dotfiles/.logs/*_claude_ntfy/events.log
#   2026-09-23T13:40:02Z backend ($3) stop: unwatched, waiter armed (debounce 600s; pts/1 not focused, input 41s ago)
#   2026-09-23T13:41:10Z backend ($3) wait: seen after 65s, no push
# An "unwatched" verdict carries what tmux knew of the session's clients
# (see clients()), so a push that should not have been sent explains itself.
# Events: stop (watched now | waiter armed | FAILED, no $TMUX_PANE or tmux
# failing), wait (coalesced | seen | session or claude's pane gone |
# transcript grew | FAILED, tmux failing), prompt (pending push cancelled),
# push (sent | FAILED with curl's exit code). The topic is never logged -- it is the capability. Only machines
# with a topic log; days over a month old are pruned with the other event
# logs (scripts/prune_logs.sh).
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
RUN_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}" # Linux tmpfs, else macOS per-user tmp

# The repo's event log. Sourced by expansion, not dirname: this also runs on
# the per-prompt cancel path, which forks nothing.
case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
# shellcheck source=scripts/lib/event_log.sh
. "$here/../../scripts/lib/event_log.sh"

# note <who> <event...>: the line "<UTC time> <who> <event>" in today's log
# (event_log_note: no fork on bash 4.2 and later once the day's directory
# exists, nothing on stdout, no prune; the waiter prunes).
note() {
  event_log_note claude_ntfy "$@" \
    || echo "ntfy-stop.sh: cannot log under $EVENT_LOG_ROOT" >&2
}

# clients <socket> <session-id> <pane>: set $clients to what tmux knows of
# the session's clients, the evidence behind a verdict of "unwatched":
#   "pts/1 not focused, input 14s ago; pts/5 focused, input 2400s ago"
#   "pts/1 focused, input 3s ago, on window 2 (claude's is 0)"
#   "pts/1 focused, input 3s ago, claude's window zoomed onto another pane"
#   "no client attached"
# The window is named only when it is not claude's, so a session of one
# window reads as before. Input seconds ago with no focus is a
# contradiction worth seeing: somebody is at that terminal, and its focus
# reports are not arriving (a terminal that resets its modes after the
# attach sends none again; 2026-09-30).
# The clients listed are those of the session claude's pane is in now --
# the hook's, unless the pane moved -- and those of the hook's session once
# the pane is gone. Best effort: this is evidence for a log line, and a
# tmux failure here has already been reported by watched().
clients() {
  local now tty flags activity win idx out="" own="" ownidx="" in="\$$2" zoomed=""
  now=${EPOCHSECONDS:-$(date +%s)}
  read -r own ownidx in zoomed <<PANE
$(tmux -S "$1" display-message -p -t "$3" '#{window_id} #{window_index} #{session_id} #{?#{&&:#{window_zoomed_flag},#{!=:#{pane_active},1}},zoomed,}' 2>/dev/null)
PANE
  in=${in:-\$$2}
  while read -r tty flags activity win idx; do
    [ -n "$tty" ] || continue
    case ",$flags," in *,focused,*) flags=focused ;; *) flags="not focused" ;; esac
    out="${out:+$out; }${tty#/dev/} $flags, input $((now - activity))s ago"
    if [ -z "$own" ]; then
      out="$out, claude's pane $3 gone"
    elif [ "$win" != "$own" ]; then
      out="$out, on window $idx (claude's is $ownidx)"
    elif [ -n "$zoomed" ]; then
      out="$out, claude's window zoomed onto another pane"
    fi
  done <<LIST
$(tmux -S "$1" list-clients -t "$in" -F '#{client_tty} #{client_flags} #{client_activity} #{window_id} #{window_index}' 2>/dev/null)
LIST
  clients=${out:-no client attached}
}

# tmux_ask <socket> <tmux args...>: run tmux, its output in $tmux_out.
# Status 0, 2 if the server is gone (the messages tmux prints when nothing
# listens on the socket), 3 on any other failure, the message in $tmux_out
# -- a client too old for the server, say -- which must not read as "gone":
# that would cancel a push without a word.
tmux_ask() {
  local socket=$1
  shift
  tmux_out=$(tmux -S "$socket" "$@" 2>&1) && return 0
  case $tmux_out in
    "no server running on "* | "error connecting to "*"(No such file or directory)" | \
      "error connecting to "*"(Connection refused)") return 2 ;;
  esac
  return 3
}

# watched <socket> <session-id> <pane>: status 0 if claude's pane is on
# screen (its window current in its session, not zoomed onto another pane)
# and a client showing that window is focused AND produced input within
# STALE_SECONDS, 1 if not, 2 if the server or the pane is gone, 3 if tmux
# failed otherwise (tmux_ask; its message in $tmux_out). Any client counts,
# not only the hook session's: a pane moved to another session is watched
# by that session's clients. The freshness bound exists because a locked/asleep Mac
# freezes the outer terminal without ever sending a focus-out, leaving
# the flag stuck at "focused" -- but a frozen terminal also sends no
# input, so activity ages past the bound and pushes resume (a Stop within
# the first STALE_SECONDS of the lock stays suppressed; that is the
# heuristic's floor). Coming back refreshes activity with no typing
# needed: the focus-in event itself counts as client input (verified), as
# do mouse scrolls. tmux evaluates the whole predicate itself via the -f
# filter; the shell only tests whether any client matched.
watched() {
  local now win
  now=${EPOCHSECONDS:-$(date +%s)} # builtin on bash 5+; forks on macOS 3.2
  # "@2", or "@2 zoomed" while the window shows another of its panes; empty
  # once the pane is gone (display-message does not fail on a missing
  # target, tmux 3.7c)
  tmux_ask "$1" display-message -p -t "$3" \
    '#{window_id}#{?#{&&:#{window_zoomed_flag},#{!=:#{pane_active},1}}, zoomed,}' || return
  win=$tmux_out
  [ -n "$win" ] || return 2
  case $win in *" zoomed") return 1 ;; esac
  tmux_ask "$1" list-clients \
    -f "#{&&:#{&&:#{m:*focused*,#{client_flags}},#{e|<:$((now - STALE_SECONDS)),#{client_activity}}},#{==:#{window_id},$win}}" \
    -F w || return
  [ -n "$tmux_out" ]
}

# lock_path <socket path> <session id>: set $lock to that session's lock
# dir. One waiter per lock; --wait and --cancel must agree on this path,
# so it is defined once. Sets a variable instead of printing to stay
# fork-free on the per-prompt --cancel path.
lock_path() { lock="$RUN_DIR/claude-ntfy/${1##*/}-$2.lock"; }

if [ "${1:-}" = --wait ]; then
  socket="$2" sid="$3" pane="$4" topic="$5" transcript="${6:-}" who="${7:-\$$3}"
  # One waiter per (socket, session): a Stop landing while one is pending
  # is the same "come look" request, so it is coalesced. mkdir is the
  # portable atomic lock; the recorded pid lets the next waiter claim a
  # crashed waiter's lock instead of wedging the session until reboot.
  # The pid file does double duty: its content is the liveness claim, its
  # mtime is the current window's start (the re-arm below refreshes it).
  lock_path "$socket" "$sid"
  mkdir -p "${lock%/*}"
  if ! mkdir "$lock" 2>/dev/null; then
    other=$(cat "$lock/pid" 2>/dev/null)
    if kill -0 "$other" 2>/dev/null; then
      note "$who" "wait: coalesced into pending waiter $other"
      exit 0
    fi
  fi
  echo $$ >"$lock/pid"
  printf '%s\n' "$who" >"$lock/who" # for --cancel's log line
  trap 'rm -rf "$lock"' EXIT

  # Prune the old logs from here, off the hook's clock: it forks, and this
  # runs once per turn (and prunes once a day). On the side, so the watch
  # below starts at once: a prune took 0.1 to 0.8 s, and its first poll is
  # timed from here. A push matters more than a tidy log directory, so a
  # prune that fails is noted and the watch goes on.
  (event_log_prune >/dev/null 2>&1 || note "$who" "log: prune_logs.sh failed") &

  start=$SECONDS
  end=$((SECONDS + DEBOUNCE_SECONDS))
  growing=0
  while [ "$SECONDS" -lt "$end" ]; do
    # Watched (0) -> the user saw it; gone (2) -> nothing to report on.
    watched "$socket" "$sid" "$pane"
    case $? in
      0)
        note "$who" "wait: seen after $((SECONDS - start))s, no push"
        exit 0
        ;;
      2)
        note "$who" "wait: session or claude's pane $pane gone, no push"
        exit 0
        ;;
      3)
        note "$who" "wait: FAILED, tmux -S $socket: $tmux_out; no push"
        exit 1
        ;;
    esac
    # Transcript grew since this window started: a new turn superseded
    # the one we are advertising (a user message alone would have fired
    # --cancel already). Restart the window; the push then fires only
    # after a full DEBOUNCE_SECONDS of quiet. A long turn grows it at
    # every poll, so only the first poll of a growth streak is logged.
    if [ -n "$transcript" ] && [ "$transcript" -nt "$lock/pid" ]; then
      echo $$ >"$lock/pid"
      end=$((SECONDS + DEBOUNCE_SECONDS))
      [ "$growing" = 1 ] || note "$who" "wait: transcript grew, window restarted"
      growing=1
    else
      growing=0
    fi
    sleep "$POLL_SECONDS"
  done

  # Resolve the name only now, once per push, from the pane: it may have
  # moved to another session. Gone since the last poll means there is
  # nothing left to come look at.
  tmux_ask "$socket" display-message -p -t "$pane" '#{session_name}'
  case $? in
    0) session=$tmux_out ;;
    2) session="" ;;
    *)
      note "$who" "wait: FAILED, tmux -S $socket: $tmux_out; no push"
      exit 1
      ;;
  esac
  if [ -z "$session" ]; then
    note "$who" "wait: session or claude's pane $pane gone, no push"
    exit 0
  fi
  curl -sf --max-time 10 \
    -H "Title: CC: $(hostname)/$session" \
    -H "Tags: speech_balloon" \
    -d "finished a turn ${DEBOUNCE_SECONDS}s ago and is still unwatched" \
    "$NTFY_URL/$topic" >/dev/null
  rc=$?
  clients "$socket" "$sid" "$pane"
  if [ "$rc" -eq 0 ]; then
    note "$who" "push: sent via $NTFY_URL after $((SECONDS - start))s unwatched ($clients)"
  else
    note "$who" "push: FAILED, curl exit $rc ($NTFY_URL; $clients)"
  fi
  exit 0
fi

# --- cancel and hook modes both run inside the session's pane, with
# $TMUX (socket-path,server-pid,session-id) identifying the session (and,
# for the hook, $TMUX_PANE claude's pane) ---
[ -n "${TMUX:-}" ] || exit 0 # not a tmux-hosted session
socket=${TMUX%%,*} sid=${TMUX##*,}

# --- cancel mode (UserPromptSubmit hook): the user answered from some
# channel, so a pending push advertises a turn they have now seen. Kill
# the waiter and free the lock; the reply's own Stop arms a fresh one.
# Runs on every prompt submission, so the common no-waiter case is pure
# builtins -- no forks. ---
if [ "${1:-}" = --cancel ]; then
  lock_path "$socket" "$sid"
  [ -d "$lock" ] || exit 0 # no waiter pending
  pid="" who=""
  IFS= read -r pid 2>/dev/null <"$lock/pid"
  IFS= read -r who 2>/dev/null <"$lock/who" # before the kill: its trap removes the lock
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -rf "$lock"
  note "${who:-\$$sid}" "prompt: user replied, pending push cancelled (waiter ${pid:-?})"
  exit 0
fi

# --- hook mode: cheap checks, then fork the waiter and get out of the way ---
# 2>/dev/null first: redirections apply left to right, so the other order
# printed "No such file or directory" on every Stop of a topic-less box.
IFS= read -r topic 2>/dev/null <"$TOPIC_FILE"
[ -n "${topic:-}" ] || exit 0
# "?" when tmux cannot say (failing: watched() below reports that).
name=$(tmux -S "$socket" display-message -p -t "\$$sid" '#{session_name}' 2>/dev/null)
who="${name:-?} (\$$sid)"
# tmux sets $TMUX_PANE beside $TMUX in every pane; without it there is no
# telling whether claude's window is the one in view, and a guess either
# way pushes wrongly or never.
if [ -z "${TMUX_PANE:-}" ]; then
  note "$who" "stop: FAILED, \$TMUX is set but \$TMUX_PANE is not"
  echo "ntfy-stop.sh: \$TMUX is set but \$TMUX_PANE is not, so the pane claude runs in is unknown; start claude in a tmux pane, or unset TMUX if it is not in one" >&2
  exit 1
fi
pane=$TMUX_PANE
watched "$socket" "$sid" "$pane"
case $? in
  0) # user is looking right now -- no waiter
    note "$who" "stop: watched now, no push"
    exit 0
    ;;
  3)
    note "$who" "stop: FAILED, tmux -S $socket: $tmux_out"
    echo "ntfy-stop.sh: tmux -S $socket failed, so whether the turn was seen is unknown: $tmux_out" >&2
    exit 1
    ;;
esac
# The hook JSON on stdin carries the conversation transcript's path; the
# waiter watches its mtime (see loop). sed, not jq: stock macOS has no jq.
transcript=$(sed -n 's/.*"transcript_path":"\([^"]*\)".*/\1/p' 2>/dev/null)

# setsid fully detaches (survives signals to claude's process group);
# stock macOS has no setsid, so fall back to nohup there.
runner=$(command -v setsid || echo nohup)
clients "$socket" "$sid" "$pane"
note "$who" "stop: unwatched, waiter armed (debounce ${DEBOUNCE_SECONDS}s; $clients)"
"$runner" "$0" --wait "$socket" "$sid" "$pane" "$topic" "$transcript" "$who" \
  </dev/null >/dev/null 2>&1 &
exit 0

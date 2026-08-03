#!/usr/bin/env bash

# Runs the tmux sessions behind claude-tmux.service on the dedicated "claude"
# socket, as configured by ~/.config/claude-tmux.conf (sourced as shell):
#
#   workdir=~/my_workspace         # directory the sessions start in
#   sessions=(backend sdk)         # extra sessions besides the built-in
#                                  # "claude" one
#
# A built-in session "claude" always runs, with --dangerously-skip-permissions;
# the sessions listed in the config run with --permission-mode auto. Each
# session resumes the Claude Code conversation named "<hostname>-<name>" if
# one exists in workdir (falling back to plain "<name>" for conversations
# that predate the prefix), otherwise it starts a new conversation with that
# name (-n) so the next boot resumes it. The prefixed name doubles as the
# Remote Control name shown on claude.ai, where sessions from every machine
# land in one list. No config at all -> just "claude" in $HOME; a config
# whose sessions are all invalid is an error.
#
#   claude_tmux_run.sh        create missing sessions, then watch (ExecStart)
#   claude_tmux_run.sh stop   kill the listed sessions (ExecStop)
#
# The unit launches this through a login zsh, so the tmux server forked from
# here inherits the full login environment (.zprofile -> ~/.profile:
# ~/.local/bin on PATH, exports) once, for every future pane and window. Each
# pane runs a plain interactive non-login zsh: .zshrc runs -- opening the
# pane's pipe-pane log -- before starting claude. With "exit-empty on" the
# dedicated server dies with the last session, so a full cold start always
# reapplies this login environment.
#
# The watcher exits as soon as any listed session is missing; the unit's
# Restart=always then reruns this script, which recreates only the missing
# sessions and leaves the rest -- including sessions created by hand on this
# socket -- untouched. The config is re-read on every poll, so a newly added
# name is picked up within seconds; a removed name keeps its session until
# it is killed by hand.

set -u

SOCKET="${CLAUDE_TMUX_SOCKET:-claude}"   # overridable so tests don't touch the live server
CONFIG_FILE="$HOME/.config/claude-tmux.conf"
HOST=$(hostname)

# Sets names and WORKDIR from the config file; called before every use so
# edits are picked up live.
load_config() {
  local n workdir=""
  local -a sessions=()
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
  # Resolve to the physical path (pwd -P): conversation lookup must encode
  # the same symlink-resolved cwd that claude itself sees in the pane.
  WORKDIR=$(cd "${workdir:-$HOME}" 2>/dev/null && pwd -P) || {
    echo "workdir '${workdir:-$HOME}' does not exist" >&2
    exit 1
  }
  names=(claude)
  local ok=
  for n in "${sessions[@]}"; do
    # The name is interpolated into a zsh -c string and must be valid for
    # both tmux (no . or :) and a Claude Code conversation title.
    if [ -z "$n" ] || [[ "$n" == *[^A-Za-z0-9_-]* ]]; then
      echo "ignoring invalid session name '$n' (use only A-Za-z0-9_-)" >&2
      continue
    fi
    ok=1
    [ "$n" = claude ] || names+=("$n")
  done
  if [ ${#sessions[@]} -gt 0 ] && [ -z "$ok" ]; then
    # Refusing beats silently running only the built-in session while the
    # user believes theirs are up; Restart+StartLimit turn this into a
    # stopped unit with a clear journal trail.
    echo "no valid session names in $CONFIG_FILE" >&2
    exit 1
  fi
}

# Print the session id of the newest conversation in WORKDIR currently named
# "$1"; print nothing if there is none. Everything Claude-Code-internal is
# confined to this function: conversations live under a directory named after
# the workdir (every character outside [A-Za-z0-9] replaced by "-") as jsonl
# files whose {"type":"custom-title","customTitle":...,"sessionId":...}
# records carry the name; the last such record wins (renames append). The ^
# anchor keeps transcript lines that merely quote such a record from matching.
resolve_conversation_id() {
  local name="$1" f rec
  local project_dir="$HOME/.claude/projects/${WORKDIR//[^a-zA-Z0-9]/-}"
  for f in $(ls -t "$project_dir"/*.jsonl 2>/dev/null); do  # uuid filenames, no spaces
    # tac + -m 1: find the last record without reading the whole transcript.
    rec=$(tac "$f" 2>/dev/null | grep -m 1 '^{"type":"custom-title"') || continue
    [[ "$rec" == *"\"customTitle\":\"$name\""* ]] || continue
    sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' <<<"$rec"
    return
  done
}

ensure_session() {
  local name="$1" conv id arg mode
  # "=$name" pins has-session/kill-session to an exact name match.
  tmux -L "$SOCKET" has-session -t "=$name" 2>/dev/null && return
  conv="$HOST-$name"
  id=$(resolve_conversation_id "$conv")
  [ -n "$id" ] || id=$(resolve_conversation_id "$name")
  if [ -n "$id" ]; then
    # Resume by id, not by name: interactive --resume with a non-id argument
    # opens the session picker instead of resuming (an empty dead-end picker
    # when nothing matches).
    arg="--resume $id"
    echo "session $name: resuming conversation $id"
  else
    arg="-n $conv"
    echo "session $name: no conversation named $conv yet, starting a new one"
  fi
  # Only the built-in session bypasses permissions.
  if [ "$name" = claude ]; then
    mode="--dangerously-skip-permissions"
  else
    mode="--permission-mode auto"
  fi
  tmux -L "$SOCKET" new-session -d -s "$name" -c "$WORKDIR" \
    /usr/bin/zsh -ic "claude $arg --remote-control $conv $mode"
}

if [ "${1:-}" = stop ]; then
  load_config
  for name in "${names[@]}"; do
    tmux -L "$SOCKET" kill-session -t "=$name" 2>/dev/null
  done
  exit 0
fi

load_config
for name in "${names[@]}"; do
  ensure_session "$name"
done

while :; do
  load_config
  for name in "${names[@]}"; do
    tmux -L "$SOCKET" has-session -t "=$name" 2>/dev/null || exit 0
  done
  sleep 5
done

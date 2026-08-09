#!/usr/bin/env bash

# The tmux + Claude Code machinery behind claude-tmux.service, and the spawn
# helper its manager session uses. All sessions live on the dedicated
# "claude" tmux socket; the Claude Code conversation behind tmux session
# <name> is named "<hostname>-<name>", which is also its Remote Control name
# on claude.ai and its local peer name (what /list-agents shows). The name
# is passed with -n on every launch, resumes included.
#
#   claude_tmux_run.sh                 ExecStart: ensure the managed "claude"
#                                      session (the manager) exists, then watch
#   claude_tmux_run.sh stop            ExecStop: kill the managed session
#   claude_tmux_run.sh spawn <name> [dir] [--dangerous]
#                                      idempotently bring up an unmanaged
#                                      session: resume its conversation where
#                                      it belongs, or start a new one in
#                                      <dir>. Auto permission mode unless
#                                      --dangerous (bypass) is given.
#
# The manager runs in ~/.dotfiles/claude_tmux_session with permissions
# bypassed; the CLAUDE.md there tells it when to call spawn. Spawned
# sessions are unmanaged: nothing recreates one that exits, and a service
# stop leaves them alone.
#
# The unit launches ExecStart through a login zsh, so the tmux server forked
# from here inherits the full login environment (.zprofile -> ~/.profile:
# ~/.local/bin on PATH, exports) once, for every future pane and window. Each
# pane runs a plain interactive non-login zsh: .zshrc runs -- opening the
# pane's pipe-pane log -- before starting claude. With "exit-empty on" the
# dedicated server dies with the last session, so a full cold start always
# reapplies this login environment.
#
# The watcher exits as soon as the managed session is missing; the unit's
# Restart=always then reruns this script.

set -u

SOCKET="${CLAUDE_TMUX_SOCKET:-claude}"   # overridable so tests don't touch the live server
HOST=$(hostname)
MANAGER_DIR="$HOME/.dotfiles/claude_tmux_session"

# Print the session id and cwd (two lines) of the newest conversation named
# "$1" among the given jsonl files; print nothing if there is none.
# Everything Claude-Code-internal is confined here: a conversation lives
# under ~/.claude/projects/<its cwd with every character outside [A-Za-z0-9]
# replaced by "-"> as a jsonl file whose
# {"type":"custom-title","customTitle":...,"sessionId":...} records carry
# the name; the last such record wins (renames append). The ^ anchor keeps
# transcript lines that merely quote such a record from matching.
resolve_conversation() {
  local conv="$1" f rec; shift
  # Cheap single-pass candidate filter, then verify only the candidates,
  # newest first. tac + -m 1 finds a file's last title record without
  # reading the whole transcript.
  for f in $(grep -l "\"customTitle\":\"$conv\"" "$@" 2>/dev/null | xargs -r ls -t); do
    rec=$(tac "$f" 2>/dev/null | grep -m 1 '^{"type":"custom-title"') || continue
    [[ "$rec" == *"\"customTitle\":\"$conv\""* ]] || continue
    sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' <<<"$rec"
    grep -m 1 -o '"cwd":"[^"]*"' "$f" | cut -d'"' -f4
    return
  done
}

# launch <session name> <dir> <claude args...>: detached pane running an
# interactive zsh (so .zshrc opens the pane's pipe-pane log) that starts
# claude with Remote Control under the conversation name.
launch() {
  local name="$1" dir="$2"; shift 2
  # Note: claude clamps its TUI to 256 colors under tmux ($TMUX set;
  # TERM/COLORTERM/FORCE_COLOR are ignored). Accepted as cosmetic --
  # hiding TMUX from claude works but is a hack; upstream should fix.
  # CLAUDE_CODE_DISABLE_AGENT_VIEW: this flow is interactive tmux sessions
  # only (see ../claude_tmux_session/CLAUDE.md). It also disables the left
  # arrow that opens the agent strip, which spawns a daemon and leaves a
  # background session behind on every press.
  tmux -L "$SOCKET" new-session -d -s "$name" -c "$dir" \
    /usr/bin/zsh -ic "CLAUDE_CODE_DISABLE_AGENT_VIEW=1 claude $* --remote-control $HOST-$name"
}

# "=$name" pins has-session/kill-session to an exact name match.
case "${1:-}" in
stop)
  tmux -L "$SOCKET" kill-session -t "=claude" 2>/dev/null
  exit 0
  ;;
spawn)
  name="${2:-}"
  # The name is interpolated into a zsh -c string and must be valid for
  # both tmux (no . or :) and a Claude Code conversation title.
  if [ -z "$name" ] || [[ "$name" == *[^A-Za-z0-9_-]* ]]; then
    echo "usage: $0 spawn <name> [dir] [--dangerous]  (name: A-Za-z0-9_- only)" >&2
    exit 1
  fi
  mode="--permission-mode auto"
  dir=""
  shift 2
  for a in "$@"; do
    case "$a" in
    --dangerous) mode="--dangerously-skip-permissions" ;;
    *) dir="$a" ;;
    esac
  done
  if tmux -L "$SOCKET" has-session -t "=$name" 2>/dev/null; then
    echo "session $name already running"
    exit 0
  fi
  conv="$HOST-$name"
  { read -r id; read -r cwd; } < <(resolve_conversation "$conv" "$HOME"/.claude/projects/*/*.jsonl)
  if [ -n "$id" ]; then
    # Refuse to resume a conversation that is already open in some other
    # claude process (a manual resume over SSH, a background agent, ...):
    # transcripts are not locked, so two processes resuming the same
    # conversation interleave their records into one corrupted history.
    # `claude agents --json` lists every live session on the machine,
    # tmux-hosted and background alike.
    # env -u: sessions run with CLAUDE_CODE_DISABLE_AGENT_VIEW=1 (see
    # launch) and a spawn issued from one inherits it, under which this
    # command prints a refusal and exits 0 -- the grep would then find
    # nothing and wave through a double-open.
    if env -u CLAUDE_CODE_DISABLE_AGENT_VIEW claude agents --json 2>/dev/null | grep -qF "$id"; then
      echo "conversation $conv ($id) is already open in another claude process; attach to that instead of spawning" >&2
      exit 1
    fi
    # Resume by id, not by name (a non-id --resume argument opens the
    # picker), in the conversation's own directory (conversations only
    # resume from the directory they belong to). -n re-asserts the name:
    # a resume by id alone reverts the session's display/peer name (what
    # /list-agents shows) to an auto-generated directory-based one.
    launch "$name" "$cwd" --resume "$id" -n "$conv" $mode
    echo "session $name: resumed conversation $id in $cwd ($mode)"
  else
    if [ ! -d "$dir" ]; then
      echo "no conversation named $conv; pass an existing directory to start a new one in" >&2
      exit 1
    fi
    launch "$name" "$dir" -n "$conv" $mode
    echo "session $name: new conversation $conv in $dir ($mode)"
  fi
  exit 0
  ;;
esac

if ! tmux -L "$SOCKET" has-session -t "=claude" 2>/dev/null; then
  { read -r id; read -r _; } < <(resolve_conversation "$HOST-claude" \
      "$HOME/.claude/projects/${MANAGER_DIR//[^a-zA-Z0-9]/-}"/*.jsonl)
  if [ -n "$id" ]; then
    launch claude "$MANAGER_DIR" --resume "$id" -n "$HOST-claude" --dangerously-skip-permissions
    echo "resuming manager conversation $id"
  else
    launch claude "$MANAGER_DIR" -n "$HOST-claude" --dangerously-skip-permissions
    echo "no manager conversation yet, starting a new one"
  fi
fi

while tmux -L "$SOCKET" has-session -t "=claude" 2>/dev/null; do sleep 5; done

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
#                                      --dangerous (bypass) is given. Reports
#                                      success only once the session has
#                                      survived startup (see wait_alive).
#   claude_tmux_run.sh status [lines]  every session on the socket: whether
#                                      claude is really running in it, which
#                                      conversation, and the tail of its pane
#   claude_tmux_run.sh conversations [pattern]
#                                      every conversation spawn could resume
#                                      on this host, with the directory it
#                                      belongs to -- what to consult before
#                                      starting a NEW one
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
ALIVE_SECONDS="${CLAUDE_TMUX_ALIVE_SECONDS:-6}"   # startup window spawn waits out

# Print the session id and cwd (two lines) of the newest conversation named
# "$1" among the given jsonl files; print nothing if there is none.
# Everything Claude-Code-internal is confined here: a conversation lives
# under ~/.claude/projects/<its cwd with every character outside [A-Za-z0-9]
# replaced by "-"> as a jsonl file whose
# {"type":"custom-title","customTitle":...,"sessionId":...} records carry
# the name; the last such record wins (renames append). The ^ anchor keeps
# transcript lines that merely quote such a record from matching.
# ~/.dotfiles/home/.config/tmux/session-color.sh reads the same records
# (from each file's tail, for macOS and cold-cache reasons) -- change both.
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

# wait_alive <session name>: true once the session has stayed up for the
# whole startup window with claude running in it. new-session returns as
# soon as it forks, so without this a caller reports success for a claude
# that exits immediately -- a rejected flag, a refused resume -- leaving no
# session behind at all, and the printed "resumed ..." is a lie. The pane
# runs `zsh -ic`, which execs claude as its last command, so once claude is
# up the pane's own process is claude; before that it is still zsh running
# .zshrc, which is why the process check only has to hold at the end.
wait_alive() {
  local name="$1" i pane_pid
  for ((i = 0; i < ALIVE_SECONDS; i++)); do
    sleep 1
    tmux -L "$SOCKET" has-session -t "=$name" 2>/dev/null || return 1
  done
  pane_pid=$(tmux -L "$SOCKET" list-panes -t "=$name" -f '#{pane_active}' \
      -F '#{pane_pid}' 2>/dev/null)
  [ -n "$pane_pid" ] || return 1
  [ "$(ps -o comm= -p "$pane_pid" 2>/dev/null)" = claude ]
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
    started="resumed conversation $id in $cwd ($mode)"
  else
    if [ ! -d "$dir" ]; then
      echo "no conversation named $conv; pass an existing directory to start a new one in" >&2
      exit 1
    fi
    launch "$name" "$dir" -n "$conv" $mode
    started="new conversation $conv in $dir ($mode)"
  fi
  # Only now is the launch worth reporting: see wait_alive.
  if ! wait_alive "$name"; then
    echo "session $name: $started -- but it exited during startup; nothing is running" >&2
    exit 1
  fi
  echo "session $name: $started"
  exit 0
  ;;
status)
  # Whether each session is really running claude, which conversation it
  # holds, and where its pane got to -- the three things worth knowing after
  # a spawn or a reboot, in one command.
  lines="${2:-6}"
  names=$(tmux -L "$SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | sort)
  if [ -z "$names" ]; then
    echo "no sessions on tmux socket $SOCKET"
    exit 0
  fi
  for s in $names; do
    read -r pane_id pane_pid pane_cwd < <(tmux -L "$SOCKET" list-panes -t "=$s" \
        -f '#{pane_active}' -F '#{pane_id} #{pane_pid} #{pane_current_path}')
    comm=$(ps -o comm= -p "$pane_pid" 2>/dev/null)
    args=$(ps -o args= -p "$pane_pid" 2>/dev/null)
    if [ "$comm" = claude ]; then
      state="claude pid $pane_pid"
    else
      state="NO CLAUDE -- pane runs ${comm:-nothing}"
    fi
    printf '== %s [%s]\n' "$s" "$state"
    printf '   dir  %s\n' "$pane_cwd"
    printf '   conv %s\n' "$(sed -n 's/.*--resume \([^ ]*\).*/\1/p' <<<"$args" | head -1)"
    # The bottom of a pane is always the same TUI chrome: the input box (two
    # rules and the prompt) plus the footer. An unfiltered tail shows only
    # that, so drop the last six lines and then any remaining rule -- the
    # box's top rule carries the session name, so "has no alphanumerics" is
    # not enough to recognise it on its own.
    tmux -L "$SOCKET" capture-pane -p -t "$pane_id" 2>/dev/null |
      head -n -6 | grep -E '[A-Za-z0-9]' |
      tail -n "$lines" | cut -c1-160 | sed 's/^/   | /'
    echo
  done
  exit 0
  ;;
conversations)
  # Every conversation spawn could resume here, newest activity per name.
  # A session name says nothing about the directory its conversation lives
  # in -- work on a subfolder is usually done from a session rooted higher
  # up -- so the only way to tell whether some existing session already
  # owns a piece of work is to look at this list. Spawning a name nobody
  # used before always succeeds, silently starting an empty second
  # conversation beside the one that has the history.
  # Conversations with no custom title are auto-named and cannot be
  # resumed by name, so they are left out; same for other hosts' names,
  # which this machine cannot spawn.
  filter="${2:-}"
  live=$(tmux -L "$SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')
  printf '%-22s %-5s %-17s %s\n' NAME LIVE 'LAST ACTIVE' DIRECTORY
  for f in "$HOME"/.claude/projects/*/*.jsonl; do
    # Same last-record-wins reading as resolve_conversation; tac stops the
    # scan at the end of the file instead of reading 200MB of transcripts.
    rec=$(tac "$f" 2>/dev/null | grep -m 1 '^{"type":"custom-title"') || continue
    title=$(sed -n 's/.*"customTitle":"\([^"]*\)".*/\1/p' <<<"$rec")
    case "$title" in "$HOST-"?*) name=${title#"$HOST-"} ;; *) continue ;; esac
    [ -z "$filter" ] || [[ "$name" == *"$filter"* ]] || continue
    printf '%s\t%s\t%s\n' "$name" "$(date -r "$f" '+%Y-%m-%d %H:%M')" \
      "$(grep -m 1 -o '"cwd":"[^"]*"' "$f" | cut -d'"' -f4)"
  done | sort -t$'\t' -k1,1 -k2,2r | awk -F'\t' '!seen[$1]++' |
    while IFS=$'\t' read -r name when dir; do
      case " $live " in *" $name "*) l=yes ;; *) l="" ;; esac
      printf '%-22s %-5s %-17s %s\n' "$name" "$l" "$when" "$dir"
    done
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

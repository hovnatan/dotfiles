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
#   claude_tmux_run.sh spawn <name>[/<task>] [dir] [--dangerous]
#                                      idempotently bring up an unmanaged
#                                      session: resume its conversation where
#                                      it belongs, or start a new one in
#                                      <dir>. <name> alone resumes the
#                                      conversation most recently talked in
#                                      under that name, labeled or not;
#                                      <name>/<task> pins the one carrying
#                                      that label. Auto permission mode unless
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
#   claude_tmux_run.sh history <name>  every conversation under one name,
#                                      newest first, with its task label and
#                                      opening prompt -- what tells the pile
#                                      a reused name accumulates apart
#
# Naming. The conversation behind tmux session <name> is titled
# "<hostname>-<name>"; once its task is clear it is labeled
# "<hostname>-<name>/<task>" (/rename inside the session, or Ctrl+R in the
# /resume picker for a finished one), which is what the picker, the prompt
# bar and claude.ai show. The tmux session follows the conversation: it is
# created under the bare <name>, and the pane-title-changed hook declared
# in ~/.tmux.conf (~/.dotfiles/home/.config/tmux/sync-session-name.sh)
# renames it <name>/<task> the moment claude announces its title, on every
# /rename after, and back to <name> after a /clear -- so `tmux ls` and the
# status bar show the label too, and this script finds a session by its
# bare name (find_session; tmux targets without "=" prefix-match as well).
# The label rides on the same record as the name, so spawn treats the bare
# name as a prefix: "backend" resumes whichever of hov-8cpu-backend and
# hov-8cpu-backend/<anything> was talked in last, and re-asserts THAT full
# title with -n, since a resume by id alone would reset it. A /clear
# carries the label into the fresh conversation, where it is wrong;
# ~/.dotfiles/home/.config/tmux/session-clear.sh strips it. The names and
# labels spawn accepts share one alphabet, NAME_RE: what tmux keeps
# verbatim (it rewrites "." and ":" to "_").
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
NAME_RE='^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)?$'       # <name>[/<task>] spawn accepts

# transcripts <mode> <conversation name> <files...>: the one reader of
# Claude Code's transcript format. A conversation lives under
# ~/.claude/projects/<its cwd with every character outside [A-Za-z0-9]
# replaced by "-"> as a jsonl file: its LAST
# {"type":"custom-title","customTitle":...,"sessionId":...} record is its
# name (renames append), the last record with a "timestamp" is when it was
# last talked in, and its head carries the cwd and the first prompt. Only
# each file's tail and head are read, in one process for all files: whole
# transcripts reach 45 MB. The name selects titles equal to it or extended
# by "/<task>" (see Naming); empty selects every titled transcript. Newest
# first, by last message, not file mtime: labeling an old conversation
# from the /resume picker rewrites its transcript without anyone talking
# in it, and by mtime that old conversation would be the one the next
# spawn resumes. A conversation with no message yet (just cleared) falls
# back to its mtime. Modes:
#   tsv      one line per match: <last talked, ISO UTC>\t<session id>\t<title>\t<cwd>\t<path>
#   history  the listing behind the history subcommand, one row per
#            conversation -- files sharing their first user message (a
#            resume into a second transcript) fold onto the newest
# ~/.dotfiles/home/.config/tmux/session-clear.sh reads the same records in
# awk (portable, no python) -- change both together.
transcripts() {
  python3 - "$@" <<'PYEOF'
import json, os, sys
from datetime import datetime, timezone

mode, conv, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
TAIL = 1 << 20   # the last title and timestamp sit within kilobytes of the end

def tail(path):
    with open(path, "rb") as fh:
        fh.seek(max(0, os.path.getsize(path) - TAIL))
        return fh.read().decode("utf-8", "replace").splitlines()

def text(content):
    if isinstance(content, list):
        return " ".join(x.get("text", "") for x in content if isinstance(x, dict) and x.get("type") == "text")
    return content if isinstance(content, str) else ""

def quoted(line, key):
    """The value of "key":"..." in a line, or None (values here carry no escapes)."""
    tag = f'"{key}":"'
    i = line.find(tag)
    if i < 0:
        return None
    i += len(tag)
    return line[i:line.index('"', i)]

rows = []
for path in paths:
    title = sid = ts = None
    for line in reversed(tail(path)):
        if title is None and line.startswith('{"type":"custom-title"'):
            rec = json.loads(line)
            title, sid = rec.get("customTitle", ""), rec.get("sessionId", "")
        if ts is None and ('"type":"user"' in line or '"type":"assistant"' in line):
            ts = quoted(line, "timestamp")   # a message: the picker orders by these too
        if title is not None and ts is not None:
            break
    if not title or (conv and title != conv and not title.startswith(conv + "/")):
        continue
    if ts is None:
        ts = datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    # The head: the cwd, and for history the first real prompt (slash
    # commands, hook output and interrupted requests say nothing about
    # the task) with its uuid, which a continuation shares.
    cwd = first = uuid = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if cwd is None:
                cwd = quoted(line, "cwd")
                if cwd is not None and mode != "history":
                    break
            if '"type":"user"' not in line:
                continue
            rec = json.loads(line)
            if rec.get("type") != "user":
                continue
            prompt = text(rec.get("message", {}).get("content")).strip()
            if not prompt or prompt.startswith(("<command-name>", "<local-command", "[Request interrupted")) or "<system-reminder>" in prompt[:40]:
                continue
            first, uuid = prompt, rec.get("uuid")
            break
    rows.append({"ts": ts, "id": sid, "title": title, "cwd": cwd or "", "path": path,
                 "first": first or "", "uuid": uuid, "size": os.path.getsize(path)})

rows.sort(key=lambda r: r["ts"], reverse=True)

if mode == "tsv":
    for r in rows:
        print(r["ts"], r["id"], r["title"], r["cwd"], r["path"], sep="\t")
    sys.exit()

folded = {}
for r in rows:
    key = r["uuid"] or r["id"]
    if key in folded:
        folded[key].setdefault("also", []).append(r["id"])
    else:
        folded[key] = r

def size(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else f"{n/1e3:.0f}K"

print(f"{'LAST ACTIVE':<17}{'SIZE':>6}  {'ID':<36}  TASK")
for r in folded.values():
    when = datetime.fromisoformat(r["ts"]).astimezone()
    task = r["title"][len(conv) + 1:] if r["title"] != conv else "-"
    print(f"{when:%Y-%m-%d %H:%M} {size(r['size']):>6}  {r['id']}  {task}")
    print(f"   {r['first'][:150] or '(no prompt yet)'}")
    if r.get("also"):
        print(f"   continued from {', '.join(r['also'])}")
    if r["cwd"]:
        print(f"   in {r['cwd']}")
PYEOF
}

# resolve_conversation <conversation name> <files...>: the session id, cwd
# and full title (three lines) of the conversation to resume for the name
# -- the newest match of transcripts -- or nothing.
resolve_conversation() {
  local conv="$1"; shift
  transcripts tsv "$conv" "$@" | awk -F'\t' 'NR == 1 { print $2; print $4; print $3 }'
}

# live_agents: every claude process on the machine, tmux-hosted or not, as
# "<pid>\t<session id>\t<current name>" lines -- the one reader of `claude
# agents --json`. env -u: sessions run with CLAUDE_CODE_DISABLE_AGENT_VIEW=1
# (see launch) and a spawn issued from one inherits it, under which the
# command prints a refusal and exits 0.
live_agents() {
  env -u CLAUDE_CODE_DISABLE_AGENT_VIEW claude agents --json 2>/dev/null |
    python3 -c 'import json, sys
for s in json.load(sys.stdin):
    print(s.get("pid", ""), s.get("sessionId", ""), s.get("name", ""), sep="\t")'
}

# agent_name <pid>, reading live_agents output: the current name of that
# claude -- what /list-agents shows, /rename included -- or nothing.
agent_name() { awk -F'\t' -v pid="$1" '$1 == pid { print $3 }'; }

# pane_pid <tmux target>: pid of the process in the target's active pane --
# the claude itself once it is up (see wait_alive) -- or nothing.
pane_pid() { tmux -L "$SOCKET" list-panes -t "$1" -f '#{pane_active}' -F '#{pane_pid}' 2>/dev/null; }

# find_session <name>: the tmux session hosting a conversation under
# <name>, whatever label it carries (<name> or <name>/<task>), or nothing.
find_session() {
  tmux -L "$SOCKET" list-sessions -F '#{session_name}' 2>/dev/null |
    grep -x -E -m 1 "$1(/.*)?"
}

# launch <session name> <dir> <claude args...>: detached pane running an
# interactive zsh (so .zshrc opens the pane's pipe-pane log) that execs
# claude with the given arguments, Remote Control named after the bare
# session name (claude.ai lists one entry per session, label or not).
# Prints the new session's id: the handle that survives the rename the
# pane-title hook applies once claude announces its title (see Naming).
# tmux hands a multi-word command to the pane as argv, untouched, so the
# arguments need no quoting; zsh -c's first operand is its $0, the rest $@.
launch() {
  local name="$1" dir="$2"; shift 2
  # Note: claude clamps its TUI to 256 colors under tmux ($TMUX set;
  # TERM/COLORTERM/FORCE_COLOR are ignored). Accepted as cosmetic --
  # hiding TMUX from claude works but is a hack; upstream should fix.
  # CLAUDE_CODE_DISABLE_AGENT_VIEW: this flow is interactive tmux sessions
  # only (see ../claude_tmux_session/CLAUDE.md). It also disables the left
  # arrow that opens the agent strip, which spawns a daemon and leaves a
  # background session behind on every press.
  tmux -L "$SOCKET" new-session -d -P -F '#{session_id}' -s "$name" -c "$dir" \
    /usr/bin/zsh -ic 'CLAUDE_CODE_DISABLE_AGENT_VIEW=1 exec claude "$@"' zsh \
    "$@" --remote-control "$HOST-$name"
}

# wait_alive <session id>: true once the session has stayed up for the
# whole startup window with claude running in it. new-session returns as
# soon as it forks, so without this a caller reports success for a claude
# that exits immediately -- a rejected flag, a refused resume -- leaving no
# session behind at all, and the printed "resumed ..." is a lie. The pane
# runs `zsh -ic`, which execs claude as its last command, so once claude is
# up the pane's own process is claude; before that it is still zsh running
# .zshrc, which is why the process check only has to hold at the end. By
# id, because the session's name changes under it (see Naming).
wait_alive() {
  local sid="$1" i pid
  for ((i = 0; i < ALIVE_SECONDS; i++)); do
    sleep 1
    tmux -L "$SOCKET" has-session -t "$sid" 2>/dev/null || return 1
  done
  pid=$(pane_pid "$sid")
  [ -n "$pid" ] && [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = claude ]
}

# "=$name" pins a tmux target to an exact name match.
case "${1:-}" in
stop)
  s=$(find_session claude)
  [ -z "$s" ] || tmux -L "$SOCKET" kill-session -t "=$s"
  exit 0
  ;;
spawn)
  spec="${2:-}"
  # <name>[/<task>]: with the hostname, the conversation title; the task
  # pins one labeled conversation (see Naming above).
  if [[ ! "$spec" =~ $NAME_RE ]]; then
    echo "usage: $0 spawn <name>[/<task>] [dir] [--dangerous]  (name and task: A-Za-z0-9_- only)" >&2
    exit 1
  fi
  name=${spec%%/*}
  mode="--permission-mode auto"
  dir=""
  shift 2
  for a in "$@"; do
    case "$a" in
    --dangerous) mode="--dangerously-skip-permissions" ;;
    *) dir="$a" ;;
    esac
  done
  conv="$HOST-$spec"
  existing=$(find_session "$name")
  if [ -n "$existing" ]; then
    # One tmux session per name: a pinned task is only satisfied when the
    # live session holds that very conversation. Switching would kill work
    # in flight, which is the user's call, not this script's.
    live=$(agent_name "$(pane_pid "=$existing")" <<<"$(live_agents)")
    if [[ "$spec" != */* ]] || [ "$live" = "$conv" ]; then
      echo "session $existing already running${live:+ ($live)}"
      exit 0
    fi
    echo "session $existing is running ${live:-an unknown conversation}, not $conv; stop it first (tmux -L $SOCKET kill-session -t $existing) or ask for it to finish" >&2
    exit 1
  fi
  { read -r id; read -r cwd; read -r title; } < <(resolve_conversation "$conv" "$HOME"/.claude/projects/*/*.jsonl)
  if [ -n "$id" ]; then
    # Refuse to resume a conversation that is already open in some other
    # claude process (a manual resume over SSH, a background agent, ...):
    # transcripts are not locked, so two processes resuming the same
    # conversation interleave their records into one corrupted history.
    if live_agents | cut -f2 | grep -qxF -- "$id"; then
      echo "conversation $conv ($id) is already open in another claude process; attach to that instead of spawning" >&2
      exit 1
    fi
    # Resume by id, not by name (a non-id --resume argument opens the
    # picker), in the conversation's own directory (conversations only
    # resume from the directory they belong to). -n re-asserts the full
    # title, label included: a resume by id alone reverts the session's
    # display/peer name (what /list-agents shows) to an auto-generated
    # directory-based one.
    sid=$(launch "$name" "$cwd" --resume "$id" -n "$title" $mode)
    started="resumed conversation $id ($title) in $cwd ($mode)"
  else
    if [ ! -d "$dir" ]; then
      echo "no conversation named $conv; pass an existing directory to start a new one in" >&2
      exit 1
    fi
    sid=$(launch "$name" "$dir" -n "$conv" $mode)
    started="new conversation $conv in $dir ($mode)"
  fi
  # Only now is the launch worth reporting: see wait_alive.
  if ! wait_alive "$sid"; then
    echo "session $name: $started -- but it exited during startup; nothing is running" >&2
    exit 1
  fi
  echo "session $(tmux -L "$SOCKET" display-message -p -t "$sid" '#{session_name}'): $started"
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
  agents=$(live_agents)
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
    printf '   conv %s %s\n' "$(sed -n 's/.*--resume \([^ ]*\).*/\1/p' <<<"$args" | head -1)" \
      "$(agent_name "$pane_pid" <<<"$agents")"
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
  # which this machine cannot spawn. One row per full title: a labeled
  # conversation is its own row (name/task), the unlabeled ones under a
  # name collapse into one -- `history <name>` tells those apart. LIVE
  # means open in a claude process right now -- the conversation, not its
  # tmux session, which hosts one of a name's many.
  filter="${2:-}"
  live=$(live_agents | cut -f3)
  printf '%-40s %-5s %-17s %s\n' NAME LIVE 'LAST ACTIVE' DIRECTORY
  transcripts tsv "" "$HOME"/.claude/projects/*/*.jsonl |
    while IFS=$'\t' read -r ts _ title cwd _; do
      case "$title" in "$HOST-"?*) name=${title#"$HOST-"} ;; *) continue ;; esac
      [ -z "$filter" ] || [[ "$name" == *"$filter"* ]] || continue
      printf '%s\t%s\t%s\t%s\n' "$name" "$ts" "$cwd" "$title"
    done | sort -t$'\t' -k1,1 -k2,2r | awk -F'\t' '!seen[$1]++' |
    while IFS=$'\t' read -r name ts cwd title; do
      if grep -qxF -- "$title" <<<"$live"; then l=yes; else l=""; fi
      printf '%-40s %-5s %-17s %s\n' "$name" "$l" "$(date -d "$ts" '+%Y-%m-%d %H:%M')" "$cwd"
    done
  exit 0
  ;;
history)
  # Every conversation under one name, newest first, with its task label
  # and opening prompt: what tells apart the pile a reused name accumulates
  # (each /clear leaves another), and where to pick the id or label that
  # `spawn <name>/<task>` or `claude --resume <id> -n <title>` needs.
  name="${2:-}"
  if [ -z "$name" ]; then
    echo "usage: $0 history <name>" >&2
    exit 1
  fi
  transcripts history "$HOST-$name" "$HOME"/.claude/projects/*/*.jsonl
  exit 0
  ;;
esac

if [ -z "$(find_session claude)" ]; then
  { read -r id; read -r _; read -r title; } < <(resolve_conversation "$HOST-claude" \
      "$HOME/.claude/projects/${MANAGER_DIR//[^a-zA-Z0-9]/-}"/*.jsonl)
  if [ -n "$id" ]; then
    launch claude "$MANAGER_DIR" --resume "$id" -n "$title" --dangerously-skip-permissions >/dev/null
    echo "resuming manager conversation $id ($title)"
  else
    launch claude "$MANAGER_DIR" -n "$HOST-claude" --dangerously-skip-permissions >/dev/null
    echo "no manager conversation yet, starting a new one"
  fi
fi

# The managed session under whatever label its conversation carries.
while [ -n "$(find_session claude)" ]; do sleep 5; done

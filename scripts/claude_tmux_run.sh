#!/usr/bin/env bash

# The tmux + Claude Code machinery behind claude-tmux.service, and the new
# and load helpers its manager session uses. All sessions live on the dedicated
# "claude" tmux socket; the Claude Code conversation behind tmux session
# <name> is named "<hostname>-<name>": a session has ONE name -- the
# prompt bar, /list-agents, the /resume picker and claude.ai all show it,
# and /rename from any of them changes it everywhere -- and claude.ai
# lists every machine's sessions, hence the hostname. The name is passed
# with -n on every launch, resumes included.
#
#   claude_tmux_run.sh serve           ExecStart: ensure the managed "claude"
#                                      session (the manager) exists, then watch;
#                                      blocks while it lives, never run by hand
#   claude_tmux_run.sh stop [name[/task]]
#                                      kill the session of exactly that name
#                                      (never a prefix of another name, and a
#                                      bare <name> never a labeled
#                                      <name>/<task>); no name: the managed
#                                      "claude" session, labeled or not
#                                      (ExecStop)
#   claude_tmux_run.sh new <name>[/<task>] <dir> [--dangerous]
#                                      start an unmanaged session on a FRESH
#                                      conversation in <dir>, whatever the
#                                      name already owns; refuses when the
#                                      session of that exact name is live, or
#                                      when <task> already labels a
#                                      conversation (load that one instead)
#   claude_tmux_run.sh load <name>[/<task>] | --id <id> [--dangerous]
#                                      idempotently bring up an unmanaged
#                                      session on an EXISTING conversation,
#                                      resumed where it belongs: <name> alone
#                                      the one most recently talked in under
#                                      that name, labeled or not;
#                                      <name>/<task> the one carrying that
#                                      label (refused when several do);
#                                      --id one picked from history. Refuses
#                                      when there is none.
#                                      Both: auto permission mode unless
#                                      --dangerous (bypass) is given; success
#                                      is reported only once the session has
#                                      survived startup (see wait_alive).
#   claude_tmux_run.sh status [lines]  every session on the socket: whether
#                                      claude is really running in it, which
#                                      conversation, and the tail of its pane
#   claude_tmux_run.sh conversations [pattern]
#                                      every conversation load could resume
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
# "<hostname>-<name>/<task>" (/label <task> inside the session or prefix L
# in tmux, both typing that /rename through
# ~/.dotfiles/home/.claude/skills/label/label-session.sh, or Ctrl+R
# in the /resume picker for a finished one), which is what the picker, the prompt
# bar and claude.ai show. The tmux session follows the conversation minus
# the hostname: it is created under that name (<name>, or <name>/<task>
# for a labeled conversation), and the
# pane-title-changed hook declared in ~/.tmux.conf
# (~/.dotfiles/home/.config/tmux/sync-session-name.sh) renames it
# <name>/<task> the moment claude announces its title, on every /rename
# after, and back to <name> after a /clear -- so `tmux ls` and the status
# bar show the label too. A full name, label included, is what has one
# live session: new, load and stop act on the exact name (api/docs runs
# beside api/login), and only the watcher looks the manager up by its bare
# name (sessions_under; tmux targets without "=" prefix-match as well). The
# label rides on the same record as the name, so load treats the bare
# name as a prefix: "backend" resumes whichever of vm-backend and
# vm-backend/<anything> was talked in last, and re-asserts THAT full
# title with -n, since a resume by id alone would reset it. That is also
# why starting a conversation is a command of its own: with backend/x
# talked in last, no form of load reaches a fresh vm-backend. A /clear
# carries the label into the fresh conversation, where it is wrong;
# ~/.dotfiles/home/.config/tmux/session-clear.sh strips it. The names and
# labels new and load accept share one alphabet, NAME_RE: what tmux keeps
# verbatim (it rewrites "." and ":" to "_"). Both hooks act only on
# sessions of this socket, where every conversation is named this way.
#
# The manager runs in ~/.dotfiles/claude_tmux_session with permissions
# bypassed; the AGENTS.md there tells it when to call new and load. Those
# sessions are unmanaged: nothing recreates one that exits, and a service
# stop leaves them alone.
#
# The unit launches ExecStart through the account's login shell (whatever
# passwd says), so the tmux server forked from here inherits the full login
# environment (~/.profile -> home/.profile.shared, reached via .zprofile when
# that shell is zsh: ~/.local/bin on PATH, EDITOR, MAKEFLAGS, ...) once, for
# every future pane and window. Each Claude pane runs that same passwd shell
# again, as a login shell, so it re-reads that environment fresh and then
# execs claude; no rc file is involved, so bash and zsh accounts behave the
# same. With "exit-empty on" the dedicated server dies with the last session,
# so a full cold start always reapplies this login environment.
#
# The watcher exits as soon as the managed session is missing; the unit's
# Restart=always then reruns this script.
#
# A session can hold more than claude: the user may open a second window in
# it. Whatever is current there, claude is found by searching the session's
# panes (claude_pane), never by taking the active one.

set -u

SOCKET="${CLAUDE_TMUX_SOCKET:-claude}" # overridable so tests don't touch the live server
HOST=$(hostname)
MANAGER_DIR="$HOME/.dotfiles/claude_tmux_session"
ALIVE_SECONDS="${CLAUDE_TMUX_ALIVE_SECONDS:-6}" # startup window new/load wait out
NAME_RE='^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)?$'    # <name>[/<task>] new/load accept

# The passwd shell, not $SHELL: a launch issued from another shell (fish, a
# tool's bash) must still launch what the account logs in with. It has to
# take `-lc <script> <$0> <args...>` like sh does; fish does not. Checked
# up front, so no subcommand gets halfway before finding out.
LOGIN_SHELL=$(getent passwd "$(id -un)" | cut -d: -f7)
case "${LOGIN_SHELL##*/}" in
  bash | zsh | sh | dash | ksh) ;;
  *)
    echo "claude_tmux_run.sh: login shell '${LOGIN_SHELL:-<none>}' cannot run 'sh -lc'-style commands; use bash or zsh as the login shell" >&2
    exit 1
    ;;
esac

# Every subcommand reads `claude agents --json` (live_agents) or launches
# claude. Checked here because live_agents runs inside $(...), where a
# failure cannot stop the script: without claude, load's already-open
# guard sees no live conversations and would double-open one. The usual
# cause is a non-login shell (a bare `ssh host cmd`): ~/.local/bin is only
# on the login PATH.
if ! command -v claude >/dev/null; then
  echo "claude_tmux_run.sh: claude is not on PATH; run it from a login shell (bash -l) or add ~/.local/bin to PATH" >&2
  exit 1
fi

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
# load resumes. A conversation with no message yet (just cleared) falls
# back to its mtime. Modes:
#   tsv      one line per match: <last talked, ISO UTC>\t<session id>\t<title>\t<cwd>\t<path>
#            (no field is ever empty -- bash's tab-separated read would
#            swallow it -- so an unknown cwd reads "-")
#   history  the listing behind the history subcommand, one row per
#            conversation -- files sharing their first user message (a
#            resume into a second transcript) fold onto the newest
#   resolve  the conversation to resume for the name: three lines (id, cwd,
#            title) of the newest match, or nothing; fails when a label is
#            carried by several conversations (folded as for history), as
#            no one of them is the one asked for
#   resolve-id  the same three lines for the conversation holding that
#            session id (the key in place of a name), resolved to its newest
#            transcript, or nothing
# ~/.dotfiles/home/.config/tmux/session-clear.sh reads the same records in
# awk (portable, no python) -- change both together.
transcripts() {
  python3 - "$@" <<'PYEOF'
import json, os, sys
from datetime import datetime, timezone

mode, key, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
conv = "" if mode == "resolve-id" else key   # the title filter; an id selects every titled one
# A directory with no transcripts yet (a fresh machine) leaves the caller's
# *.jsonl glob unexpanded; that literal pattern means "no conversations".
paths = [p for p in paths if not p.endswith("/*.jsonl")]
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

def head_cwd(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            cwd = quoted(line, "cwd")
            if cwd is not None:
                return cwd
    return None

dir_cwd = {}
def sibling_cwd(path):
    """A conversation with no message yet (just cleared, then the session
    died) records no cwd, but every transcript in a project directory
    shares one: take a sibling's."""
    d = os.path.dirname(path)
    if d not in dir_cwd:
        dir_cwd[d] = next((c for f in os.listdir(d) if f.endswith(".jsonl")
                           for c in [head_cwd(os.path.join(d, f))] if c), None)
    return dir_cwd[d]

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
                if cwd is not None and mode == "tsv":
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
    rows.append({"ts": ts, "id": sid, "title": title, "cwd": cwd or sibling_cwd(path) or "-", "path": path,
                 "first": first or "", "uuid": uuid, "size": os.path.getsize(path)})

rows.sort(key=lambda r: r["ts"], reverse=True)

if mode == "tsv":
    for r in rows:
        print(r["ts"], r["id"], r["title"], r["cwd"], r["path"], sep="\t")
    sys.exit()

def fold(rows):
    """One row per conversation, newest first, each carrying the ids of the
    older transcripts folded onto it in "also"."""
    folded = {}
    for r in rows:
        k = r["uuid"] or r["id"]
        if k in folded:
            folded[k].setdefault("also", []).append(r["id"])
        else:
            folded[k] = r
    return list(folded.values())

if mode in ("resolve", "resolve-id"):
    if mode == "resolve-id":
        rows = [r for r in fold(rows) if key == r["id"] or key in r.get("also", [])]
    elif "/" in conv:
        carriers = fold([r for r in rows if r["title"] == conv])
        if len(carriers) > 1:
            sys.exit(f"claude_tmux_run.sh: {conv} labels {len(carriers)} conversations ("
                     + ", ".join(r["id"] for r in carriers)
                     + "); pick one with load --id <id> (history tells them apart), and relabel the others")
    if rows:
        print(rows[0]["id"], rows[0]["cwd"], rows[0]["title"], sep="\n")
    sys.exit()

def size(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else f"{n/1e3:.0f}K"

print(f"{'LAST ACTIVE':<17}{'SIZE':>6}  {'ID':<36}  TASK")
for r in fold(rows):
    when = datetime.fromisoformat(r["ts"]).astimezone()
    task = r["title"][len(conv) + 1:] if r["title"] != conv else "-"
    print(f"{when:%Y-%m-%d %H:%M} {size(r['size']):>6}  {r['id']}  {task}")
    print(f"   {r['first'][:150] or '(no prompt yet)'}")
    if r.get("also"):
        print(f"   continued from {', '.join(r['also'])}")
    print(f"   in {r['cwd']}")
PYEOF
}

# find_conversation resolve|resolve-id <name or id> <files...>: sets id,
# cwd and title of the conversation to resume (see transcripts), all empty
# when there is none. Exits on a failure -- a label several conversations
# carry -- which inside a bare $(...) could not stop the script.
find_conversation() {
  local found
  found=$(transcripts "$@") || exit 1
  {
    read -r id
    read -r cwd
    read -r title
  } <<<"$found"
}

# live_agents: every claude process on the machine, tmux-hosted or not, as
# "<pid>\t<session id>\t<current name>" lines -- the one reader of `claude
# agents --json`. env -u: sessions run with CLAUDE_CODE_DISABLE_AGENT_VIEW=1
# (see launch) and a load issued from one inherits it, under which the
# command prints a refusal and exits 0.
# Fails (non-zero, with the reason on stderr) when the command fails or its
# output is not a list of agents. Callers must stop then: an empty answer
# would read as "nothing is open", and load would resume a conversation
# another process holds -- the double-open its guard exists to prevent.
# Each caller captures it in an assignment, `x=$(live_agents) || exit 1`,
# since a failure inside a bare $(...) cannot stop the script.
live_agents() {
  local json
  json=$(env -u CLAUDE_CODE_DISABLE_AGENT_VIEW claude agents --json) || {
    echo "claude_tmux_run.sh: 'claude agents --json' failed; cannot tell which conversations are open" >&2
    return 1
  }
  python3 -c 'import json, sys
try:
    agents = json.loads(sys.argv[1])
    assert isinstance(agents, list) and all(isinstance(a, dict) for a in agents)
except (ValueError, AssertionError):
    sys.exit("claude_tmux_run.sh: claude agents --json printed no list of agents: " + sys.argv[1][:200])
for s in agents:
    print(s.get("pid", ""), s.get("sessionId", ""), s.get("name", ""), sep="\t")' "$json"
}

# agent_name <pid>, reading live_agents output: the current name of that
# claude -- what /list-agents shows, /rename included -- or nothing.
agent_name() { awk -F'\t' -v pid="$1" '$1 == pid { print $3 }'; }
# agent_id <pid>, likewise: the session id that claude has open.
agent_id() { awk -F'\t' -v pid="$1" '$1 == pid { print $2 }'; }

# claude_pane <session>: "<pane id> <pid> <cwd>" of the pane in that
# session whose process is claude -- the one the session was created with,
# once claude is up (see wait_alive) -- or nothing. Every window of the
# session is searched, not just the active pane: with a second window the
# user opened current, the active pane runs a shell, and a healthy session
# would read as dead. The session is "=<name>" or a session id ("$3"); the
# ":" appended makes tmux resolve it as a session: list-panes takes a
# window target, and a bare "=claude" from inside tmux first matches a
# window named "claude" in the CURRENT session (every claude pane's window
# is named that), i.e. some other session's pane.
claude_pane() {
  local id pid cwd
  while read -r id pid cwd; do
    if [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = claude ]; then
      echo "$id $pid $cwd"
      return
    fi
  done < <(tmux -L "$SOCKET" list-panes -s -t "$1:" -F '#{pane_id} #{pane_pid} #{pane_current_path}' 2>/dev/null)
}

# sessions_under <name>: every tmux session hosting a conversation under
# <name>, whatever label it carries (<name> or <name>/<task>), one per
# line, sorted -- several when conversations of one name run side by side
# (api, api/login, api/docs). Nothing when no server is running, the one
# failure that means "none". Any other (a client too old to talk to the
# server, ...) is reported and returns 1: read as "none", it would let
# ExecStop report success with the manager still up. -e: NAME_RE allows a
# leading "-", which grep would parse as an option.
sessions_under() {
  local out
  if ! out=$(tmux -L "$SOCKET" list-sessions -F '#{session_name}' 2>&1); then
    case "$out" in
      "no server running on "* | "error connecting to "*"(No such file or directory)" | \
        "error connecting to "*"(Connection refused)") return 0 ;;
    esac
    echo "claude_tmux_run.sh: tmux -L $SOCKET list-sessions failed: $out" >&2
    return 1
  fi
  grep -x -E -e "$1(/.*)?" <<<"$out" | LC_ALL=C sort
  return 0
}

# find_session <name>: the first of sessions_under <name>, or nothing.
find_session() { sessions_under "$1" | head -n 1; }

# launch <session name> <dir> <claude args...>: detached pane running the
# account's login shell (LOGIN_SHELL, from passwd) as a login shell, which execs claude with
# the given arguments and Remote Control on (claude.ai shows the session's
# one name, the -n among the arguments).
# Prints the new session's id: the handle that survives the rename the
# pane-title hook applies once claude announces its title (see Naming).
# tmux hands a multi-word command to the pane as argv, untouched, so the
# arguments need no quoting; -c's first operand is the shell's $0, the rest $@.
launch() {
  local name="$1" dir="$2"
  shift 2

  # Note: claude clamps its TUI to 256 colors under tmux ($TMUX set;
  # TERM/COLORTERM/FORCE_COLOR are ignored). Accepted as cosmetic --
  # hiding TMUX from claude works but is a hack; upstream should fix.
  # CLAUDE_CODE_DISABLE_AGENT_VIEW: this flow is interactive tmux sessions
  # only (see ../claude_tmux_session/AGENTS.md). It also disables the left
  # arrow that opens the agent strip, which spawns a daemon and leaves a
  # background session behind on every press.

  # The systemd unit the tmux server lives in, and why it is not the service.
  # tmux >= 3.7 marks every pane's scope PartOf= the unit its server was
  # started from. Forked from ExecStart that unit is claude-tmux.service, so
  # `systemctl --user stop|restart claude-tmux` would take down every session
  # -- the unmanaged ones included -- where it should kill only the manager.
  # The new-session that starts the server therefore runs in a scope of its
  # own, which then owns the panes:
  #
  #   claude-tmux.service        watch loop; ExecStop kills only "claude"
  #   tmux-server-claude.scope   tmux server  <--PartOf--  tmux-spawn-*.scope
  #                                                        (one per pane)
  #
  # Stopping that scope does end every session, as it is the server. Only
  # the first new-session needs it: with "exit-empty on" the server exists
  # exactly while some session does, and later calls just talk to it. A
  # failure (no user systemd manager) stops the launch with systemd-run's
  # own error rather than quietly starting the server inside the service.
  local scope=()
  if ! tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; then
    scope=(systemd-run --user --scope --quiet --collect
      --unit="tmux-server-$SOCKET"
      --description="tmux server for the $SOCKET socket (claude_tmux_run.sh)")
  fi
  "${scope[@]}" tmux -L "$SOCKET" new-session -d -P -F '#{session_id}' \
    -s "$name" -c "$dir" \
    "$LOGIN_SHELL" -lc 'CLAUDE_CODE_DISABLE_AGENT_VIEW=1 exec claude "$@"' "${LOGIN_SHELL##*/}" \
    "$@" --remote-control
}

# wait_alive <session id>: true once the session has stayed up for the
# whole startup window with claude running in it. new-session returns as
# soon as it forks, so without this a caller reports success for a claude
# that exits immediately -- a rejected flag, a refused resume -- leaving no
# session behind at all, and the printed "resumed ..." is a lie. The pane
# runs the login shell with -lc, which execs claude as its last command, so
# once claude is up the pane's own process is claude; before that it is
# still the shell reading its profile, which is why the process check only
# has to hold at the end. By
# id, because the session's name changes under it (see Naming).
wait_alive() {
  local sid="$1" i
  for ((i = 0; i < ALIVE_SECONDS; i++)); do
    sleep 1
    tmux -L "$SOCKET" has-session -t "$sid" 2>/dev/null || return 1
  done
  [ -n "$(claude_pane "$sid")" ]
}

# parse_args <usage> <count> <args...>: the arguments new and load share.
# Sets mode (claude's permission flags: auto, or bypass for --dangerous) and
# rest (the others, exactly <count> of them -- a directory given to load
# would be ignored for the conversation's own, a second one to new half
# lost); a mismatch prints <usage> and exits.
parse_args() {
  local usage=$1 want=$2 a
  # An array, so `--permission-mode auto` stays two arguments without an
  # unquoted expansion.
  mode=(--permission-mode auto)
  rest=()
  for a in "${@:3}"; do
    case "$a" in
      --dangerous) mode=(--dangerously-skip-permissions) ;;
      *) rest+=("$a") ;;
    esac
  done
  if [ "${#rest[@]}" -ne "$want" ]; then
    echo "$usage" >&2
    exit 1
  fi
}

# start_session <session name> <dir> <what> <claude args...>: launch, wait
# out the startup window, and report "session <name>: <what>" once claude
# survived it -- only then is the launch worth reporting (see wait_alive).
# Fails, saying so, when it did not.
start_session() {
  local target=$1 dir=$2 what=$3 sid
  shift 3
  sid=$(launch "$target" "$dir" "$@") || return 1
  if ! wait_alive "$sid"; then
    echo "session $target: $what -- but it exited during startup; nothing is running" >&2
    return 1
  fi
  echo "session $(tmux -L "$SOCKET" display-message -p -t "$sid" '#{session_name}'): $what"
}

# resume_session <session name> <dir> <claude args...>: resume the
# conversation find_conversation found (id, title) through start_session.
# Refuses one already open in another claude process (a manual resume over
# SSH, a background agent, ...): transcripts are not locked, so two
# processes resuming the same conversation interleave their records into
# one corrupted history. By id, not by name (a non-id --resume argument
# opens the picker); -n re-asserts the full title, label included: a resume
# by id alone reverts the session's display/peer name (what /list-agents
# shows) to an auto-generated directory-based one.
resume_session() {
  local target=$1 dir=$2 agents
  shift 2
  agents=$(live_agents) || return 1
  if cut -f2 <<<"$agents" | grep -qxF -- "$id"; then
    echo "conversation $title ($id) is already open in another claude process; attach to that instead of loading it" >&2
    return 1
  fi
  start_session "$target" "$dir" "resumed conversation $id ($title) in $dir ($*)" --resume "$id" -n "$title" "$@"
}

# "=$name" pins a tmux target to an exact name match.
case "${1:-}" in
  stop)
    # Without a name (ExecStop): the manager, whatever label it carries, and
    # a missing one is fine. With one: the session of exactly that name,
    # killed by "=" -- a bare tmux target prefix-matches, so
    # `kill-session -t api` with no api left kills api2 -- and a bare
    # <name> never reaches a labeled <name>/<task>, which holds a different
    # conversation: `stop api` beside api/login and api/docs
    # kills api or nothing. A miss lists the labeled ones to pick from.
    # Only the bare name is checked against NAME_RE: a label set by hand
    # (/rename, the /resume picker) can hold any character but a space, and
    # the session carrying it must still be stoppable by its full name.
    if [ $# -lt 2 ]; then
      s=$(sessions_under claude) || exit 1
      s=${s%%$'\n'*}
      [ -z "$s" ] && exit 0
    else
      s="$2"
      if [[ ! "${s%%/*}" =~ $NAME_RE ]] || [[ "$s" == */ ]]; then
        echo "usage: $0 stop [name[/task]]  (name: A-Za-z0-9_- only; task: as status prints it)" >&2
        exit 1
      fi
      under=$(sessions_under "${s%%/*}") || exit 1
      if ! grep -qxF -e "$s" <<<"$under"; then
        echo "no session $s on tmux socket $SOCKET${under:+; under that name: ${under//$'\n'/ } (stop one by its full name)}" >&2
        exit 1
      fi
    fi
    tmux -L "$SOCKET" kill-session -t "=$s" && echo "stopped session $s"
    exit
    ;;
  new)
    # A FRESH conversation, whatever the name owns already (see Naming for
    # why this is not load's job). The cheap refusals come first: the
    # transcript scan reads every transcript's head and tail.
    usage="usage: $0 new <name>[/<task>] <dir> [--dangerous]  (name and task: A-Za-z0-9_- only)"
    parse_args "$usage" 2 "${@:2}"
    spec=${rest[0]} dir=${rest[1]}
    conv="$HOST-$spec"
    if [[ ! "$spec" =~ $NAME_RE ]]; then
      echo "$usage" >&2
      exit 1
    fi
    if [ ! -d "$dir" ]; then
      echo "new: '$dir' is not a directory; pass an existing one to start the conversation in" >&2
      exit 1
    fi
    # One live session per full name (see load); the live one holds some
    # other conversation by definition.
    under=$(sessions_under "${spec%%/*}") || exit 1
    if grep -qxF -e "$spec" <<<"$under"; then
      echo "new: session $spec is already running; stop it first ($0 stop $spec), load it, or pick another name or label" >&2
      exit 1
    fi
    # A bare name owns many conversations (one per /clear), but a label pins
    # ONE: a second carrier would make `load <name>/<task>` refuse both.
    if [[ "$spec" == */* ]]; then
      find_conversation resolve "$conv" "$HOME"/.claude/projects/*/*.jsonl
      if [ -n "$id" ]; then
        echo "new: conversation $title ($id) already carries that label; load it ($0 load $spec) or pick another label" >&2
        exit 1
      fi
    fi
    start_session "$spec" "$dir" "new conversation $conv in $dir (${mode[*]})" -n "$conv" "${mode[@]}"
    exit
    ;;
  load)
    # By <name>[/<task>], or by --id: the way to an unlabeled conversation
    # that is no longer the newest under its name, with the guards below.
    usage="usage: $0 load <name>[/<task>] | --id <id> [--dangerous]  (resumes in the conversation's own directory; ids: $0 history <name>)"
    spec=""
    if [ "${2:-}" = --id ]; then
      parse_args "$usage" 1 "${@:3}"
      find_conversation resolve-id "${rest[0]}" "$HOME"/.claude/projects/*/*.jsonl
      if [ -z "$id" ]; then
        echo "load: no titled conversation has id ${rest[0]} ($0 history <name> lists them)" >&2
        exit 1
      fi
    else
      parse_args "$usage" 1 "${@:2}"
      spec=${rest[0]}
      if [[ ! "$spec" =~ $NAME_RE ]]; then
        echo "$usage" >&2
        exit 1
      fi
      find_conversation resolve "$HOST-$spec" "$HOME"/.claude/projects/*/*.jsonl
      if [ -z "$id" ]; then
        echo "load: no conversation named $HOST-$spec; $0 new $spec <dir> starts one ($0 conversations lists what exists)" >&2
        exit 1
      fi
    fi
    # The session a conversation runs in carries its title minus the
    # hostname -- api/docs for <host>-api/docs, whichever spec found it. An
    # id can reach a conversation titled otherwise (by hand), which names no
    # session.
    target=${title#"$HOST-"}
    if [ "$target" = "$title" ] || [[ ! "$target" =~ $NAME_RE ]]; then
      echo "load: conversation $id is titled '$title', which names no session ($HOST-<name>[/<task>]); rename it from the /resume picker (Ctrl+R) first" >&2
      exit 1
    fi

    # One live session per FULL name: api, api/login and api/docs are
    # three names and run side by side; what cannot happen is a second
    # session of one of them. Already up is success when the live session
    # holds what was asked for -- any conversation of a bare name, the
    # labeled one, the very id; switching it would kill work in flight,
    # which is the user's call, not this script's.
    under=$(sessions_under "${target%%/*}") || exit 1
    if grep -qxF -e "$target" <<<"$under"; then
      agents=$(live_agents) || exit 1
      read -r _ pid _ < <(claude_pane "=$target")
      live=$(agent_name "${pid:-}" <<<"$agents")
      if [ -n "$spec" ] && [[ "$spec" != */* ]]; then
        ok=1
      elif [ -n "$spec" ]; then
        ok=$([ "$live" = "$title" ] && echo 1)
      else
        ok=$([ "$(agent_id "${pid:-}" <<<"$agents")" = "$id" ] && echo 1)
      fi
      if [ -n "$ok" ]; then
        echo "session $target already running${live:+ ($live)}"
        exit 0
      fi
      echo "session $target is running ${live:-an unknown conversation}, not $title ($id); stop it first ($0 stop $target) or ask for it to finish" >&2
      exit 1
    fi

    if [ "$cwd" = - ]; then
      echo "conversation $title ($id) records no working directory and neither does any transcript beside it; resume it by hand from the right directory" >&2
      exit 1
    fi
    resume_session "$target" "$cwd" "${mode[@]}"
    exit
    ;;
  status)
    # Whether each session is really running claude, which conversation it
    # holds, and where its pane got to -- the three things worth knowing after
    # a new, a load or a reboot, in one command.
    lines="${2:-6}"
    names=$(tmux -L "$SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | sort)
    if [ -z "$names" ]; then
      echo "no sessions on tmux socket $SOCKET"
      exit 0
    fi
    agents=$(live_agents) || exit 1
    for s in $names; do
      # The claude pane wherever it is; with none, the session's first pane
      # (the one it was created with) shows what runs instead.
      pane=$(claude_pane "=$s")
      [ -n "$pane" ] || pane=$(tmux -L "$SOCKET" list-panes -s -t "=$s:" \
        -F '#{pane_id} #{pane_pid} #{pane_current_path}' | head -1)
      read -r pane_id pane_pid pane_cwd <<<"$pane"
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
      tmux -L "$SOCKET" capture-pane -p -t "$pane_id" 2>/dev/null \
        | head -n -6 | grep -E '[A-Za-z0-9]' \
        | tail -n "$lines" | cut -c1-160 | sed 's/^/   | /'
      echo
    done
    exit 0
    ;;
  conversations)
    # Every conversation load could resume here, newest activity per name.
    # A session name says nothing about the directory its conversation lives
    # in -- work on a subfolder is usually done from a session rooted higher
    # up -- so the only way to tell whether some existing session already
    # owns a piece of work is to look at this list. `new` under a name nobody
    # used before always succeeds, silently starting an empty second
    # conversation beside the one that has the history.
    # Conversations with no custom title are auto-named; one without this
    # host's prefix, or whose rest is outside the session-name alphabet (a
    # hand-typed sentence), cannot be a session here: all left out. One row
    # per full title: a labeled
    # conversation is its own row (name/task), the unlabeled ones under a
    # name collapse into one -- `history <name>` tells those apart. LIVE
    # means open in a claude process right now -- the conversation, not its
    # tmux session, which hosts one of a name's many.
    filter="${2:-}"
    live=$(live_agents) || exit 1
    live=$(cut -f3 <<<"$live")
    printf '%-40s %-5s %-17s %s\n' NAME LIVE 'LAST ACTIVE' DIRECTORY
    transcripts tsv "" "$HOME"/.claude/projects/*/*.jsonl \
      | while IFS=$'\t' read -r ts _ title cwd _; do
        name=${title#"$HOST-"}
        [ "$name" != "$title" ] && [[ "$name" =~ $NAME_RE ]] || continue
        [ -z "$filter" ] || [[ "$name" == *"$filter"* ]] || continue
        printf '%s\t%s\t%s\t%s\n' "$name" "$ts" "$cwd" "$title"
      done | sort -t$'\t' -k1,1 -k2,2r | awk -F'\t' '!seen[$1]++' \
      | while IFS=$'\t' read -r name ts cwd title; do
        if grep -qxF -- "$title" <<<"$live"; then l=yes; else l=""; fi
        printf '%-40s %-5s %-17s %s\n' "$name" "$l" "$(date -d "$ts" '+%Y-%m-%d %H:%M')" "$cwd"
      done
    exit 0
    ;;
  history)
    # Every conversation under one name, newest first, with its task label
    # and opening prompt: what tells apart the pile a reused name accumulates
    # (each /clear leaves another), and where to pick the id or label that
    # `load <name>/<task>` or `load --id <id>` needs.
    name="${2:-}"
    if [ -z "$name" ]; then
      echo "usage: $0 history <name>" >&2
      exit 1
    fi
    transcripts history "$HOST-$name" "$HOME"/.claude/projects/*/*.jsonl
    exit 0
    ;;
  serve)
    # ExecStart. An explicit subcommand, so no mistyped or bare call reaches
    # a loop that blocks forever. Being one case arm, it is parsed whole --
    # the exit included -- before it runs: the watcher never reads this file
    # again, so an edit to it mid-run cannot feed it half a new script.
    if [ $# -ne 1 ]; then
      echo "usage: $0 serve  (claude-tmux.service's ExecStart; takes no arguments)" >&2
      exit 1
    fi
    if [ -z "$(find_session claude)" ]; then
      find_conversation resolve "$HOST-claude" \
        "$HOME/.claude/projects/${MANAGER_DIR//[^a-zA-Z0-9]/-}"/*.jsonl
      if [ -n "$id" ]; then
        resume_session claude "$MANAGER_DIR" --dangerously-skip-permissions || exit 1
      else
        start_session claude "$MANAGER_DIR" "new conversation $HOST-claude in $MANAGER_DIR" \
          -n "$HOST-claude" --dangerously-skip-permissions || exit 1
      fi
    fi
    # The managed session under whatever label its conversation carries.
    while [ -n "$(find_session claude)" ]; do sleep 5; done
    exit 0
    ;;
  *)
    {
      echo "usage: $0 serve|new|load|stop|status|conversations|history ...  (got '${1:-}'; the header of $0 lists each one's arguments)"
      # The unit ran this bare before serve existed, and systemd keeps a
      # unit as it last read it.
      [ -n "${1:-}" ] || echo "  claude-tmux.service runs '$0 serve'; a unit calling it bare was loaded before that: systemctl --user daemon-reload && systemctl --user restart claude-tmux"
    } >&2
    exit 1
    ;;
esac

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
#   claude_tmux_run.sh restart [--check|--force] <name>[/<task>]
#                                      restart claude IN PLACE in the session
#                                      of exactly that name: same tmux
#                                      session and pane (attached clients stay
#                                      put), same conversation resumed with
#                                      the launch's permission mode -- a fresh
#                                      binary after an update. Refuses a
#                                      busy session (a turn or background
#                                      shells) unless --force; --check only
#                                      checks, printing that work. prefix C-r in
#                                      ~/.tmux.conf runs it on the session in
#                                      view.
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
# <name>/<task> the moment claude announces its title, and again on every
# /rename after -- so `tmux ls` and the status bar show the label too. A full name, label included, is what has one
# live session: new, load and stop act on the exact name (api/docs runs
# beside api/login), and only the watcher looks the manager up by its bare
# name (sessions_under; tmux targets without "=" prefix-match as well). The
# label rides on the same record as the name, so load treats the bare
# name as a prefix: "backend" resumes whichever of vm-backend and
# vm-backend/<anything> was talked in last, and re-asserts THAT full
# title with -n, since a resume by id alone would reset it. That is also
# why starting a conversation is a command of its own: with backend/x
# talked in last, no form of load reaches a fresh vm-backend. A /clear
# carries the label into the fresh conversation; nothing strips it, so
# relabel (or /rename to the bare name) when the new work differs. The
# names and labels new and load accept share one alphabet, NAME_RE: what
# tmux keeps verbatim (it rewrites "." and ":" to "_"). The hook acts only
# on sessions of this socket, where every conversation is named this way.
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
# How long restart lets claude shut down after TERM before KILL: past its own
# failsafe, which exits it within max(5 s, SessionEnd hook timeout + 5 s).
EXIT_SECONDS="${CLAUDE_TMUX_EXIT_SECONDS:-30}"

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
# replaced by "-"; past 200 characters, cut there plus a hash (2.1.303)> as
# <session id>.jsonl -- so a lookup by id globs every project directory
# rather than building the name (serve's MANAGER_DIR is short): its LAST
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
# "<pid>\t<session id>\t<current name>\t<status>" lines (status: idle, or
# busy while a turn runs) -- the one reader of `claude
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
  # Every key is required: each agent carries all four (2.1.303; one never
  # named gets an auto name), and a missing one is a changed format, which
  # read as "" would pass for "no such agent" or "not idle".
  python3 -c 'import json, sys
try:
    agents = json.loads(sys.argv[1])
    assert isinstance(agents, list) and all(isinstance(a, dict) for a in agents)
except (ValueError, AssertionError):
    sys.exit("claude_tmux_run.sh: claude agents --json printed no list of agents: " + sys.argv[1][:200])
for s in agents:
    missing = [k for k in ("pid", "sessionId", "name", "status") if k not in s]
    if missing:
        sys.exit(f"claude_tmux_run.sh: claude agents --json has an agent without {missing} (format changed?): {s}")
    print(s["pid"], s["sessionId"], s["name"], s["status"], sep="\t")' "$json"
}

# agent_name <pid>, reading live_agents output: the current name of that
# claude -- what /list-agents shows, /rename included -- or nothing.
agent_name() { awk -F'\t' -v pid="$1" '$1 == pid { print $3 }'; }
# agent_id <pid>, likewise: the session id that claude has open.
agent_id() { awk -F'\t' -v pid="$1" '$1 == pid { print $2 }'; }
# agent_status <pid>, likewise: idle, or busy while a turn runs.
agent_status() { awk -F'\t' -v pid="$1" '$1 == pid { print $4 }'; }

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

# exact_session <subcommand> <name>[/<task>]: exits, saying why, unless the
# session of exactly that name is live -- the check stop and restart act
# behind, so a bare <name> never reaches a labeled <name>/<task>, which
# holds a different conversation, and a miss lists the labeled ones to
# pick from. Only the bare name is checked against NAME_RE: a label set by
# hand (/rename, the /resume picker) can hold any character but a space,
# and the session carrying it must still be reachable by its full name.
exact_session() {
  local cmd=$1 s=$2 under
  if [[ ! "${s%%/*}" =~ $NAME_RE ]] || [[ "$s" == */ ]]; then
    echo "usage: $0 $cmd <name>[/<task>]  (name: A-Za-z0-9_- only; task: as status prints it)" >&2
    exit 1
  fi
  under=$(sessions_under "${s%%/*}") || exit 1
  if ! grep -qxF -e "$s" <<<"$under"; then
    echo "no session $s on tmux socket $SOCKET${under:+; under that name: ${under//$'\n'/ } ($cmd one by its full name)}" >&2
    exit 1
  fi
}

# tmux_quote <args...>: the arguments as one tmux command-line string that
# tmux's parser splits back into exactly them -- for a command tmux runs
# later from a string (a hook). Single quotes take everything literally;
# an argument holding one goes in double quotes, where \, " and $ are
# escaped. 'a b' "it's" '#{x}' come back as a b, it's, #{x}.
tmux_quote() {
  local a out=""
  for a in "$@"; do
    if [[ "$a" != *"'"* ]]; then
      out+=" '$a'"
    else
      a=${a//\\/\\\\} a=${a//\"/\\\"} a=${a//\$/\\\$}
      out+=" \"$a\""
    fi
  done
  printf '%s' "${out# }"
}

# bg_shells <claude pid>: the shells that claude still tracks, one
# "<pid> <command>" line each. Its Bash tool runs every command as a child
#   bash -c source ~/.claude/shell-snapshots/<s>.sh ... && eval '<command>' < /dev/null ...
# so with no turn running, such a child is a background task or a Monitor;
# its MCP servers and helpers (hunspell) are children too, but not of that
# form. Killing claude ends these with no completion record.
bg_shells() {
  ps -A -o ppid=,pid=,args= | awk -v p="$1" '$1 == p && /\.claude\/shell-snapshots\// { $1 = ""; print }' \
    | sed -e "s/^ *\([0-9]*\) .* && eval '\(.*\)' < \/dev\/null .*/\1 \2/" -e "s/'\"'\"'/'/g"
}

# The command every claude pane runs, its claude arguments appended (see
# launch, and restart, which respawns a pane with it).
PANE_CMD=("$LOGIN_SHELL" -lc 'CLAUDE_CODE_DISABLE_AGENT_VIEW=1 exec claude "$@"' "${LOGIN_SHELL##*/}")

# launch <session name> <dir> <claude args...>: detached pane running the
# account's login shell (LOGIN_SHELL, from passwd) as a login shell, which execs claude with
# the given arguments and Remote Control on (claude.ai shows the session's
# one name, the -n among the arguments).
# Prints the new pane's id: the handle that survives the rename the
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
  "${scope[@]}" tmux -L "$SOCKET" new-session -d -P -F '#{pane_id}' \
    -s "$name" -c "$dir" "${PANE_CMD[@]}" "$@" --remote-control
}

# pane_proc <pane>: "<pane_dead> <pane_pid>" of that pane; fails once the
# pane is gone (its process exited and nothing kept it).
pane_proc() { tmux -L "$SOCKET" display-message -p -t "$1" '#{pane_dead} #{pane_pid}' 2>/dev/null; }

# wait_alive <pane id>: whether claude came up in that pane and survived
# the startup window. new-session and respawn-pane return as soon as they
# fork, so without this a caller reports success for a claude that exits
# at once -- a rejected flag, a refused resume -- and the printed
# "resumed ..." is a lie. Two phases, as the pane runs the login shell
# with -lc, which reads the profile and then execs claude:
#
#   shell (profile) --exec--> claude --ALIVE_SECONDS--> up       return 0
#        |   still the shell after 60 s (a stuck profile)        return 2
#        +--------------------+--- pane dead or gone             return 1
#
# The shell phase is waited out however long it takes up to that bound: a
# slow profile on a loaded box is not a failed start. By pane id, which
# survives the session's renames (see Naming).
wait_alive() {
  local pane=$1 i state
  for ((i = 0; ; i++)); do
    state=$(pane_proc "$pane") && [ "${state% *}" = 0 ] || return 1
    [ "$(ps -o comm= -p "${state#* }" 2>/dev/null)" = claude ] && break
    [ "$i" -lt 240 ] || return 2
    sleep 0.25
  done
  for ((i = 0; i < ALIVE_SECONDS; i++)); do
    sleep 1
    state=$(pane_proc "$pane") && [ "${state% *}" = 0 ] || return 1
  done
  [ "$(ps -o comm= -p "${state#* }" 2>/dev/null)" = claude ]
}

# started <pane id> <what>: wait_alive's verdict as one line, "session
# <name>: <what>" on stdout when claude is up, the failure on stderr
# (status 1) otherwise.
started() {
  local pane=$1 what=$2 rc=0
  wait_alive "$pane" || rc=$?
  case $rc in
    0) echo "session $(tmux -L "$SOCKET" display-message -p -t "$pane" '#{session_name}'): $what" ;;
    2) echo "pane $pane: $what -- but its login shell has not started claude after 60 s; see what it is stuck on (tmux -L $SOCKET capture-pane -p -t $pane)" >&2 ;;
    *) echo "pane $pane: $what -- but claude exited during startup; nothing is running there" >&2 ;;
  esac
  [ "$rc" -eq 0 ]
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
# out the startup, and report "session <name>: <what>" once claude survived
# it -- only then is the launch worth reporting (see wait_alive). Fails,
# saying so, when it did not.
start_session() {
  local target=$1 dir=$2 what=$3 pane
  shift 3
  pane=$(launch "$target" "$dir" "$@") || return 1
  started "$pane" "$what"
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
    # kills api or nothing (exact_session).
    if [ $# -lt 2 ]; then
      s=$(sessions_under claude) || exit 1
      s=${s%%$'\n'*}
      [ -z "$s" ] && exit 0
    else
      s="$2"
      exact_session stop "$s"
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
  restart)
    # A fresh claude in the same pane, on the same conversation: what a
    # Claude Code update needs. stop + load does it too, but destroys the
    # session, so every client attached to it detaches (or jumps to another
    # session) and has to be pointed back. Here the pane survives, and tmux
    # itself does the respawn, from a pane-died hook armed before the kill:
    #
    #   checks   all before the kill; a refusal leaves claude running
    #   arm      this pane only: remain-on-exit on, pane-died hook
    #   TERM --> claude exits, however long its shutdown takes
    #            hook (tmux): respawn-pane PANE_CMD --resume <id> -n <title>
    #            <mode>, then unset the hook and remain-on-exit
    #   wait     for the respawn; a claude still up after EXIT_SECONDS gets KILL
    #   report   wait_alive on the new claude
    #
    # The respawn and the disarm are one command list the server runs, so
    # once TERM is sent the restart completes and the pane ends up as before
    # whatever happens to this script: interrupted (Esc on the manager's
    # Bash call), killed, or timed out waiting on a slow shutdown.
    #
    # Refused unless --force: work a restart would kill -- a turn, or a
    # background shell claude tracks (bg_shells) -- read just before
    # arming. agents --json cannot tell the two apart: it reports "busy"
    # for as long as a background shell runs, the turn long over (2.1.303),
    # but the pane shows which, so the call is the user's. --check runs
    # every check, kills nothing, and prints that work as one line instead
    # of refusing over it: what prefix C-r puts in its prompt
    # (~/.dotfiles/home/.config/tmux/restart-claude.sh) before a forced
    # restart. Always refused: a conversation also open in another process
    # (two writers corrupt one transcript), and a pane not launched here,
    # whose start command names no permission mode to keep (auto, or bypass
    # for --dangerous).
    # The directory is the conversation's own, from its transcript
    # (find_conversation), not claude's cwd, which EnterWorktree moves.
    usage="usage: $0 restart [--check|--force] <name>[/<task>]  (the exact session name, as status prints it)"
    check="" force="" operands=()
    for a in "${@:2}"; do
      case "$a" in
        --check) check=1 ;;
        --force) force=1 ;;
        *) operands+=("$a") ;;
      esac
    done
    if [ "${#operands[@]}" -ne 1 ]; then
      echo "$usage" >&2
      exit 1
    fi
    s=${operands[0]}
    exact_session restart "$s"
    read -r pane pid _ < <(claude_pane "=$s")
    if [ -z "${pane:-}" ]; then
      echo "restart: no claude running in session $s; $0 stop $s, then $0 load $s" >&2
      exit 1
    fi

    # The conversation that claude has open, and how its pane was launched.
    agents=$(live_agents) || exit 1
    live_id=$(agent_id "$pid" <<<"$agents")
    live_title=$(agent_name "$pid" <<<"$agents")
    if [ -z "$live_id" ]; then
      echo "restart: claude $pid in session $s is not among 'claude agents --json'; cannot tell which conversation to resume" >&2
      exit 1
    fi
    if awk -F'\t' -v pid="$pid" -v id="$live_id" '$2 == id && $1 != pid { f = 1 } END { exit !f }' <<<"$agents"; then
      echo "restart: conversation $live_title ($live_id) is also open in another claude process; close that one first" >&2
      exit 1
    fi
    start=$(tmux -L "$SOCKET" display-message -p -t "$pane" '#{pane_start_command}') || exit 1
    case " $start " in
      *" --dangerously-skip-permissions "*) mode=(--dangerously-skip-permissions) ;;
      *" --permission-mode auto "*) mode=(--permission-mode auto) ;;
      *)
        echo "restart: session $s was not started by $0 (its pane runs: $start); restart it by hand" >&2
        exit 1
        ;;
    esac
    find_conversation resolve-id "$live_id" "$HOME"/.claude/projects/*/*.jsonl
    if [ -z "$id" ] || [ "$cwd" = - ]; then
      echo "restart: no titled transcript with a directory holds conversation $live_id (claude $pid in session $s); left running" >&2
      exit 1
    fi

    # idle_check: what a restart would kill, as one line in "work" --
    #   busy: a turn, or 1 background shell(s): sleep 900
    # -- empty when claude is idle with no shells. Refused unless --force;
    # --check prints it. Asked after the slow transcript lookup, so that
    # little can start between it and the arming (a remote-control message
    # could start a turn).
    idle_check() {
      local state shells
      agents=$(live_agents) || exit 1
      state=$(agent_status "$pid" <<<"$agents")
      shells=$(bg_shells "$pid")
      work=""
      [ "$state" = idle ] || work="$state: a turn"
      if [ -n "$shells" ]; then
        work+="${work:+, or }$(wc -l <<<"$shells" | tr -d ' ') background shell(s): $(cut -d' ' -f2- <<<"$shells" | paste -sd ';' -)"
      fi
      if [ -n "$check" ]; then
        [ -z "$work" ] || echo "$work"
      elif [ -n "$work" ] && [ -z "$force" ]; then
        echo "restart: session $s is not idle ($work), which a restart kills; wait for it (Esc ends a turn), or --force" >&2
        exit 1
      fi
    }
    idle_check
    [ -z "$check" ] || exit 0

    # From here on every step is logged, the log's path printed first.
    . "$(dirname "$0")/lib/event_log.sh"
    event_log_start claude_tmux_restart || exit 1
    echo "log: $EVENT_LOG_FILE"
    say() { log "$s: $*"; }
    die() {
      log "$s: FAILED $*" >&2
      exit 1
    }
    say "claude $pid, conversation $live_id ($live_title), dir $cwd, ${mode[*]}${work:+; forced over $work}"

    # Arm. Until TERM goes out a signal disarms, so an interrupted restart
    # leaves no hook behind to resume a claude that exits later on its own.
    disarm() {
      tmux -L "$SOCKET" set-hook -p -u -t "$pane" pane-died
      tmux -L "$SOCKET" set-option -p -u -t "$pane" remain-on-exit
    }
    trap 'disarm; die "interrupted before the kill; claude $pid left running"' INT TERM HUP
    hook="respawn-pane -t $pane -c $(tmux_quote "$cwd") $(tmux_quote "${PANE_CMD[@]}" \
      --resume "$live_id" -n "$live_title" "${mode[@]}" --remote-control)"
    hook+=" ; set-hook -p -u -t $pane pane-died ; set-option -p -u -t $pane remain-on-exit"
    if ! tmux -L "$SOCKET" set-option -p -t "$pane" remain-on-exit on \
      || ! tmux -L "$SOCKET" set-hook -p -t "$pane" pane-died "$hook"; then
      disarm 2>/dev/null
      die "could not arm pane $pane (gone?); claude $pid left running"
    fi
    say "armed pane $pane: tmux resumes the conversation when claude $pid exits"
    kill -TERM "$pid" || say "TERM to claude $pid failed: it already exited, which fires the hook as well"
    trap - INT TERM HUP
    say "sent TERM to claude $pid"

    # respawned: wait until the pane runs something other than <pid>.
    respawned() {
      local i
      for ((i = 0; i < $2 * 4; i++)); do
        state=$(pane_proc "$pane") || die "pane $pane is gone; $0 load $s brings the conversation back"
        [ "${state#* }" != "$1" ] && return 0
        sleep 0.25
      done
      return 1
    }
    if ! respawned "$pid" "$EXIT_SECONDS"; then
      say "claude $pid still up $EXIT_SECONDS s after TERM; sending KILL"
      kill -KILL "$pid"
      respawned "$pid" 5 || die "claude $pid survived KILL; the armed hook resumes the conversation once it exits"
    fi
    say "respawned: pane $pane runs pid ${state#* }; waiting for claude"
    if msg=$(started "$pane" "restarted conversation $live_id ($live_title) in $cwd (${mode[*]})" 2>&1); then
      log "$msg" # "session <name>: ...", the name already in it
    else
      die "$msg; $0 load $s brings it back"
    fi
    exit 0
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
    # KillMode=process signals only this shell, so a foreground sleep would
    # outlive it in the unit's cgroup ("left-over process" on the next
    # start); waited on in the background, the TERM trap can take it along.
    nap=""
    trap 'kill "$nap" 2>/dev/null; exit 0' TERM
    while [ -n "$(find_session claude)" ]; do
      sleep 5 &
      nap=$!
      wait "$nap"
    done
    exit 0
    ;;
  *)
    {
      echo "usage: $0 serve|new|load|restart|stop|status|conversations|history ...  (got '${1:-}'; the header of $0 lists each one's arguments)"
      # The unit ran this bare before serve existed, and systemd keeps a
      # unit as it last read it.
      [ -n "${1:-}" ] || echo "  claude-tmux.service runs '$0 serve'; a unit calling it bare was loaded before that: systemctl --user daemon-reload && systemctl --user restart claude-tmux"
    } >&2
    exit 1
    ;;
esac

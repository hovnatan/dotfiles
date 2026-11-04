#!/usr/bin/env bash

# The tmux + Claude Code machinery behind claude-tmux.service, and the new
# and load helpers its manager session uses. All sessions live on the dedicated
# "claude" tmux socket; the Claude Code conversation behind tmux session
# <name> is named "<hostname>/<name>": a session has ONE name -- the
# prompt bar, /list-agents, the /resume picker and claude.ai all show it,
# and /rename from any of them changes it everywhere -- and claude.ai
# lists every machine's sessions, hence the hostname. The name is passed
# with -n on every launch, resumes included.
#
#   claude_tmux_run.sh start           ExecStart, at boot: start the managed
#                                      "manager" session unless it exists,
#                                      then return; nothing watches it after
#   claude_tmux_run.sh stop [name[/task]]
#                                      kill the session of exactly that name
#                                      (never a prefix of another name, and a
#                                      bare <name> never a labeled
#                                      <name>/<task>); no name: the managed
#                                      "manager" session, labeled or not
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
#                                      or bring claude back into a live
#                                      session it exited from (as window 0,
#                                      beside the windows still open there),
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
#   claude_tmux_run.sh restart [--check|--force] --pane <socket path> <pane id>
#                                      restart claude IN PLACE in the session
#                                      of exactly that name: same tmux
#                                      session and pane (attached clients stay
#                                      put), same conversation resumed with
#                                      the launch's permission mode -- a fresh
#                                      binary after an update. Refuses a
#                                      busy session (a turn or background
#                                      shells) unless --force; --check only
#                                      checks, printing that work and the
#                                      detached processes the restart ends
#                                      (never a refusal), one per line,
#                                      programs by full path. --pane: the
#                                      claude in that pane's foreground, on
#                                      any tmux server; one typed at a
#                                      shell's prompt is resumed at that
#                                      prompt. prefix C-r in ~/.tmux.conf
#                                      runs it on what in-view picks.
#   claude_tmux_run.sh in-view <socket path> <pane id>
#                                      what prefix C-r restarts with that
#                                      pane in view: prints "pane" (restart
#                                      --pane) or "session" (restart <name>)
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
# "<hostname>/<name>"; once its task is clear it is labeled
# "<hostname>/<name>/<task>" (/rename inside the session, or Ctrl+R in
# the /resume picker for a finished one), which is what the picker, the prompt
# bar and claude.ai show. The tmux session follows the conversation minus
# the hostname: it is created under that name (<name>, or <name>/<task>
# for a labeled conversation), and the
# pane-title-changed hook declared in ~/.tmux.conf
# (~/.dotfiles/home/.config/tmux/sync-session-name.sh) renames it
# <name>/<task> the moment claude announces its title, and again on every
# /rename after -- so `tmux ls` and the status bar show the label too. A full name, label included, is what has one
# live session: new, load and stop act on the exact name (api/docs runs
# beside api/login), and only start and a bare stop look the manager up by its bare
# name (sessions_under; tmux targets without "=" prefix-match as well). The
# label rides on the same record as the name, so load treats the bare
# name as a prefix: "backend" resumes whichever of vm/backend and
# vm/backend/<anything> was talked in last, and re-asserts THAT full
# title with -n, since a resume by id alone would reset it. That is also
# why starting a conversation is a command of its own: with backend/x
# talked in last, no form of load reaches a fresh vm/backend. A /clear
# carries the label into the fresh conversation; nothing strips it, so
# relabel (or /rename to the bare name) when the new work differs. The
# names and labels new and load accept share one alphabet, NAME_RE: what
# tmux keeps verbatim (it rewrites "." and ":" to "_"). The hook acts only
# on sessions of this socket, where every conversation is named this way.
#
# The manager runs in ~/.dotfiles/claude_tmux_session with permissions
# bypassed; the AGENTS.md there tells it when to call new and load. Nothing
# recreates a session that exits, the manager included: the unit starts
# the manager at boot (and on `systemctl --user start claude-tmux`, when
# its session is gone) and watches nothing after, and a service stop leaves
# every session alone.
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
# A session can hold more than claude: the user may open more windows in
# it (nvim, a shell; prefix C). Claude stays window 0, and whatever is
# current there, it is found by searching the session's panes
# (claude_pane), never by taking the active one. With other windows open,
# claude exiting (/exit, a crash, an OOM kill) leaves the session alive
# without it:
#
#   session api                             claude_pane  claude_launched
#     0 claude (PANE_CMD), running claude      %4           %4
#     0 PANE_CMD, its login shell starting     -            %4   (load, restart)
#     -- claude exited, window gone --         -            -
#     1 nvim                                  (kept)
#
#   load api       live, no claude launched -> resumes into a new window 0
#                  (new-window -b before the others), the others untouched
#   start          the manager's session in that state -> left alone (it
#                  exists); `load manager --dangerous` resumes it into it
#   restart api    nothing to restart -> points at load
#
# A pane still starting claude (launched, not yet exec'd) counts as having
# one: a load acting then would start a second claude beside it.

set -u

SOCKET="${CLAUDE_TMUX_SOCKET:-claude}" # overridable so tests don't touch the live server
# The tmux server every command here talks to: the claude socket's, or,
# for `restart --pane`, the one at the socket path it is given (any server:
# a Mac's default one).
TMUX_SERVER=(-L "$SOCKET")
tm() { tmux "${TMUX_SERVER[@]}" "$@"; }
HOST=$(hostname)
MANAGER_DIR="$HOME/.dotfiles/claude_tmux_session"
ALIVE_SECONDS="${CLAUDE_TMUX_ALIVE_SECONDS:-6}" # startup window new/load wait out
NAME_RE='^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)?$'    # <name>[/<task>] new/load accept
# The conversation behind session <name>[/<task>] is "$CONV<name>[/<task>]":
# "/" after the hostname, which no hostname contains, so the split is never
# ambiguous ("vm/api/docs"). Until 2026-10-22 it was "<hostname>-",
# and conversations and live sessions still carry that form: every lookup
# reads both (canon_title here, canon() in transcripts), and every load and
# restart re-asserts the title with -n in the new form, so a conversation
# moves over the next time it is brought up.
#   canon_title vm-api/docs -> vm/api/docs; vm/api/docs and x-y unchanged
CONV="$HOST/"
canon_title() {
  case $1 in
    "$HOST-"*) printf '%s\n' "$CONV${1#"$HOST-"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
# canon_titles: canon_title on every line of stdin.
canon_titles() { awk -v h="$HOST" '{ if (index($0, h "-") == 1) $0 = h "/" substr($0, length(h) + 2); print }'; }
# The manager's tmux session; its conversation is "<hostname>/manager".
# Until 2026-10-22 it was "claude", like the socket.
MANAGER=manager
# How long restart lets claude shut down after TERM before KILL: past its own
# failsafe, which exits it within max(5 s, SessionEnd hook timeout + 5 s).
EXIT_SECONDS="${CLAUDE_TMUX_EXIT_SECONDS:-30}"

# The passwd shell, not $SHELL: a launch issued from another shell (fish, a
# tool's bash) must still launch what the account logs in with. It has to
# take `-lc <script> <$0> <args...>` like sh does; fish does not. Checked
# up front, so no subcommand gets halfway before finding out -- but for
# restart, which checks once it knows it respawns a pane with PANE_CMD: a
# claude typed at a shell's prompt is resumed at that prompt (a Mac's fish
# under tmux), whatever the login shell. macOS has no getent; its
# directory service holds the same field.
case $(uname) in
  Darwin) LOGIN_SHELL=$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | sed -n 's/^UserShell: //p') ;;
  *) LOGIN_SHELL=$(getent passwd "$(id -un)" | cut -d: -f7) ;;
esac
login_shell_ok() {
  case "${LOGIN_SHELL##*/}" in
    bash | zsh | sh | dash | ksh) ;;
    *)
      echo "claude_tmux_run.sh: login shell '${LOGIN_SHELL:-<none>}' cannot run 'sh -lc'-style commands; use bash or zsh as the login shell" >&2
      return 1
      ;;
  esac
}
case "${1:-}" in
  restart | in-view) ;;
  *) login_shell_ok || exit 1 ;;
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
# rather than building the name (start's MANAGER_DIR is short): its LAST
# {"type":"custom-title","customTitle":...,"sessionId":...} record is its
# name (renames append), the last record with a "timestamp" is when it was
# last talked in, and its head carries the cwd and the first prompt. Only
# each file's tail and head are read, in one process for all files: whole
# transcripts reach 45 MB. The name selects titles equal to it or extended
# by "/<task>" (see Naming); a title in the old "<hostname>-" form is read,
# and printed, in the new one. Empty selects every titled transcript. Newest
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
#   resolve  the conversation to resume for the name: four lines (id, cwd,
#            title, permission mode: "-", read for resolve-id only) of the
#            newest match, or nothing; fails when a label is carried by
#            several conversations (folded as for history), as no one of
#            them is the one asked for
#   resolve-id  the same four lines for the conversation holding that
#            session id (the key in place of a name), resolved to its newest
#            transcript, or nothing. Untitled ones count here (title ""): a
#            claude started by hand at a prompt, never renamed, has only the
#            auto-generated name claude agents shows, and an AI title of its
#            own. The permission mode is the last one a prompt of the
#            transcript of that very id recorded ("permissionMode", Shift-Tab
#            changes included), read through the whole file, as one long turn
#            pushes the last prompt out of any tail; "-" when it holds none.
#            A newer untitled transcript folded onto a titled one keeps the
#            title
transcripts() {
  CTR_HOST="$HOST" python3 - "$@" <<'PYEOF'
import json, os, sys
from datetime import datetime, timezone

mode, key, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
HOST = os.environ["CTR_HOST"]

def canon(title):
    """The title in the current "<host>/" form (canon_title in the script)."""
    return HOST + "/" + title[len(HOST) + 1:] if title.startswith(HOST + "-") else title

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

def last_mode(path):
    mode = "-"
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if '"type":"user"' in line:
                mode = quoted(line, "permissionMode") or mode
    return mode

rows = []
by_id = mode == "resolve-id"
for path in paths:
    title = sid = ts = None
    for line in reversed(tail(path)):
        if title is None and line.startswith('{"type":"custom-title"'):
            rec = json.loads(line)
            title, sid = canon(rec.get("customTitle", "")), rec.get("sessionId", "")
        if ts is None and ('"type":"user"' in line or '"type":"assistant"' in line):
            ts = quoted(line, "timestamp")   # a message: the picker orders by these too
        if title is not None and ts is not None:
            break
    if not title and by_id:
        # The file is named after the session id the custom-title record
        # would carry: <id>.jsonl.
        title, sid = "", os.path.basename(path)[:-len(".jsonl")]
    if not title and not by_id or (conv and title != conv and not title.startswith(conv + "/")):
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
            folded[k]["title"] = folded[k]["title"] or r["title"]
        else:
            folded[k] = r
    return list(folded.values())

if mode in ("resolve", "resolve-id"):
    exact = None
    if mode == "resolve-id":
        exact = next((r for r in rows if r["id"] == key), None)
        rows = [r for r in fold(rows) if key == r["id"] or key in r.get("also", [])]
    elif "/" in conv.removeprefix(HOST + "/"):
        carriers = fold([r for r in rows if r["title"] == conv])
        if len(carriers) > 1:
            sys.exit(f"claude_tmux_run.sh: {conv} labels {len(carriers)} conversations ("
                     + ", ".join(r["id"] for r in carriers)
                     + "); pick one with load --id <id> (history tells them apart), and relabel the others")
    if rows:
        print(rows[0]["id"], rows[0]["cwd"], rows[0]["title"],
              last_mode((exact or rows[0])["path"]) if by_id else "-", sep="\n")
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
# cwd, title and pmode (its last permission mode, resolve-id only) of the
# conversation to resume (see transcripts), all empty when there is none.
# Exits on a failure -- a label several conversations carry -- which inside
# a bare $(...) could not stop the script.
find_conversation() {
  local found
  found=$(transcripts "$@") || exit 1
  {
    read -r id
    read -r cwd
    read -r title
    read -r pmode
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
  done < <(tm list-panes -s -t "$1:" -F '#{pane_id} #{pane_pid} #{pane_current_path}' 2>/dev/null)
}

# claude_launched <session>: the id of the live pane in that session started
# with PANE_CMD -- running claude, or its login shell still starting it --
# or nothing. What claude_pane misses while a launch or a restart is under
# way (the pane's process is the login shell then, not claude), and what
# load and launch ask before starting a claude of their own into a session.
# The start command is how tmux shows it, e.g.
#   /bin/bash -lc "CLAUDE_CODE_DISABLE_AGENT_VIEW=1 exec claude \"$@\"" bash --resume ...
# A dead pane does not count: restart's pane-died hook respawns the pane as
# claude dies, so one left dead is a respawn that failed (its directory
# gone, ...), and counting it would have load and restart answer "starting"
# for as long as it sits there.
claude_launched() {
  tm list-panes -s -t "$1:" -F '#{?pane_dead,,#{pane_id} #{pane_start_command}}' 2>/dev/null \
    | awk -v m="$PANE_MARK" 'index($0, m) { print $1; exit }'
}

# sessions_under <name>: every tmux session hosting a conversation under
# <name>, whatever label it carries (<name> or <name>/<task>), one per
# line, sorted -- several when conversations of one name run side by side
# (api, api/login, api/docs). Nothing when no server is running, the one
# failure that means "none". Any other (a client too old to talk to the
# server, ...) is reported and returns 1: read as "none", it would let
# a bare stop report success with the manager still up. -e: NAME_RE allows a
# leading "-", which grep would parse as an option.
sessions_under() {
  local out
  if ! out=$(tm list-sessions -F '#{session_name}' 2>&1); then
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

# find_session <name>: the first of sessions_under <name>, or nothing; fails
# as sessions_under does (a pipe into head would report head's status, and
# a tmux failure would read as "no session").
find_session() {
  local out
  out=$(sessions_under "$1") || return 1
  echo "${out%%$'\n'*}"
}

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
#   bash -c source ~/.claude/shell-snapshots/<s>.sh ... && eval '<command>' < /dev/null && pwd -P >| <cwd file>
# (no "< /dev/null" when the command redirects stdin itself), so with no
# turn running, such a child is a background task or a Monitor; its MCP
# servers and helpers (hunspell) are children too, but not of that form.
# Killing claude ends these with no completion record.
bg_shells() {
  # The command runs from the FIRST "&& eval '" (the wrapper's; the command
  # may hold another) to the wrapper's tail at the end of the line, its
  # quotes unescaped ('"'"' -> '). A line of another form is still a shell
  # claude tracks: it is listed whole, never dropped.
  ps -A -o ppid=,pid=,args= | awk -v p="$1" '
    $1 == p && /\.claude\/shell-snapshots\// {
      pid = $2
      sub(/^ *[0-9]+ +[0-9]+ /, "")
      cmd = $0
      i = index(cmd, " && eval '\''")
      if (i) cmd = substr(cmd, i + 10)
      if (i && sub(/'\''( < \/dev\/null)? && pwd -P >\| [^ ]*$/, "", cmd)) {
        gsub(/'\''"'\''"'\''/, "'\''", cmd)
      } else cmd = $0
      print pid, cmd
    }'
}

# scope_of <pid>: the systemd unit the process runs in, from the unified
# (cgroup v2) line of /proc/<pid>/cgroup -- a pane's own scope under
# tmux >= 3.7, "tmux-spawn-<uuid>.scope"; empty when /proc has none.
scope_of() {
  local cg
  cg=$(sed -n 's/^0:://p' "/proc/$1/cgroup" 2>/dev/null)
  echo "${cg##*/}"
}

# detached <scope> [<pid>]: "<pid> <args>" per process in <scope> that is
# neither <pid> nor its descendant (every process in it, with no <pid>) --
# what was started from the pane and detached (setsid, nohup &, a double
# fork), so reparented off <pid> and still running in its scope:
#   tmux-spawn-a.scope  claude 10, its shell 11 (child), proxy 12 (ppid 1)
#   detached tmux-spawn-a.scope 10  ->  "12 cloud-sql-proxy --port 5432"
detached() {
  local cg
  cg=$(systemctl --user show -p ControlGroup --value "$1")
  [ -n "$cg" ] && [ -r "/sys/fs/cgroup$cg/cgroup.procs" ] || return 0
  # In pid order, so a listing reads the same twice.
  ps -A -o pid=,ppid=,args= | awk -v root="${2:-}" '
    NR == FNR { scope[$1] = 1; next }
    { p = $1; pp[p] = $2; sub(/^ *[0-9]+ +[0-9]+ /, ""); args[p] = $0 }
    END {
      if (root != "") mine[root] = 1
      do {
        grew = 0
        for (p in pp) if (!(p in mine) && (pp[p] in mine)) { mine[p] = 1; grew = 1 }
      } while (grew)
      for (p in scope) if (!(p in mine) && (p in args)) print p, args[p]
    }' "/sys/fs/cgroup$cg/cgroup.procs" - | sort -n
}

# program <pid>: what the process runs, for a person to recognise: the full
# path of its executable, from /proc (argv[0] is often a bare "ssh" found
# through PATH), and the name it was started under when that differs (a
# multi-call binary, a versioned file behind a symlink):
#   12 ssh        ->  /usr/bin/ssh
#   13 tail       ->  /usr/bin/busybox (tail)
#   14 claude     ->  /home/u/.local/share/claude/versions/2.1.309 (claude)
#   15 ssh-agent  ->  ssh-agent (path not readable)
# The name is comm, the basename of the path exec was given (cut to 15
# characters by the kernel), not argv[0]: a program may rewrite its argv,
# and an ssh ControlMaster does, to "ssh: <socket> [mux]", whose first word
# would read "ssh:". The last: the kernel hides the exe link of a setuid or
# setgid program (ssh-agent is setgid on Ubuntu), and of one that made
# itself non-dumpable; comm is then all there is.
program() {
  local exe base comm
  comm=$(cat "/proc/$1/comm")
  exe=$(readlink "/proc/$1/exe" 2>/dev/null) || {
    echo "$comm (path not readable)"
    return
  }
  base=${exe##*/}
  base=${base% (deleted)}
  if [ "${base:0:15}" = "$comm" ]; then echo "$exe"; else echo "$exe ($comm)"; fi
}

# fg_claude <pane pid>: the pid of the process group holding that pane's
# terminal when it is a claude (comm is a full path on macOS), else nothing.
fg_claude() {
  local fg comm
  fg=$(ps -o tpgid= -p "$1" 2>/dev/null | tr -d ' ')
  comm=$(ps -o comm= -p "${fg:-0}" 2>/dev/null)
  [ "${comm##*/}" != claude ] || echo "$fg"
}

# cwd_of <pid>: the working directory of that process, from /proc on Linux
# and lsof on macOS, which has no /proc; nothing when it cannot be read.
cwd_of() {
  if [ -d /proc/self ]; then
    readlink "/proc/$1/cwd"
  else
    lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p'
  fi
}

# shell_words <shell> <words...>: the words as one command line that
# shell's parser splits back into exactly them, for typing at its prompt.
# Plain words go as they are (no leading "=", which zsh expands); others
# in single quotes, which every shell here takes literally but for fish's
# two escapes in them, \\ and \' -- in the POSIX shells a ' ends them, so
# one is written '\'':
#   fish  claude -n "it's a\b"  ->  claude -n 'it\'s a\\b'
#   bash  claude -n "it's a\b"  ->  claude -n 'it'\''s a\b'
shell_words() {
  local sh=$1 w out=""
  shift
  for w in "$@"; do
    if [[ "$w" =~ ^[A-Za-z0-9_./:@+,-][A-Za-z0-9_./:@+,=-]*$ ]]; then
      out+=" $w"
    elif [ "$sh" = fish ]; then
      w=${w//\\/\\\\} w=${w//\'/\\\'}
      out+=" '$w'"
    else
      out+=" '${w//\'/\'\\\'\'}'"
    fi
  done
  printf '%s' "${out# }"
}

# The command every claude pane runs, its claude arguments appended (see
# launch, and restart, which respawns a pane with it).
PANE_MARK='CLAUDE_CODE_DISABLE_AGENT_VIEW=1 exec claude' # what claude_launched looks for
PANE_CMD=("$LOGIN_SHELL" -lc "$PANE_MARK"' "$@"' "${LOGIN_SHELL##*/}")

# launch <session name> <dir> <claude args...>: detached pane running the
# account's login shell (LOGIN_SHELL, from passwd) as a login shell, which execs claude with
# the given arguments and Remote Control on (claude.ai shows the session's
# one name, the -n among the arguments). A new session of that name, or,
# when the session is live (claude gone from it, see the header), a new
# window 0 in it: before the first window when 0 is taken (renumber-windows
# closes the gap claude's window left, so it usually is), so claude is
# window 0 again and the others keep their order. -d: a client typing in
# nvim there stays where it is.
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
  # -- the manager's included -- where it should touch none.
  # The new-session that starts the server therefore runs in a scope of its
  # own, which then owns the panes:
  #
  #   claude-tmux.service        oneshot: start ran and returned, no process
  #   tmux-server-claude.scope   tmux server  <--PartOf--  tmux-spawn-*.scope
  #                                                        (one per pane)
  #
  # Stopping that scope does end every session, as it is the server. Only
  # the first new-session needs it: with "exit-empty on" the server exists
  # exactly while some session does, and later calls just talk to it. A
  # failure (no user systemd manager) stops the launch with systemd-run's
  # own error rather than quietly starting the server inside the service.
  #
  # A scope of that name can outlive its server: a pane's scope that a
  # session's background job keeps alive holds it loaded (PartOf), and
  # systemd-run would be refused. reap-panes.sh --server-gone stops those
  # pane scopes first and waits for the name to come free; the
  # session-closed hook does the same for every session but the last.
  #
  # One launch at a time per socket. Callers check for a claude first and
  # launch after (load and start, the cold start too), so two of them at
  # once -- start at boot while the user loads the manager, two loads --
  # would both find none and both start one: two claudes in a session, one
  # conversation resumed twice (its transcript interleaved). Under the lock
  # the check is made again, and the second launch refuses. flock, not
  # tmux's wait-for -L: a launch killed while holding a wait-for lock would
  # wedge every later one until the server exits; flock's ends with its fd.
  # The fd is closed for the tmux client that starts the server, which
  # would otherwise hold the lock for the server's lifetime.
  #
  #   launch A --flock--> no claude --> new-window/new-session --> unlock
  #   launch B --flock (waits)-----------------------------------> claude in
  #                                                     pane %N: refuse
  local scope=() at lock pane
  : "${XDG_RUNTIME_DIR:?launch: XDG_RUNTIME_DIR is unset (no user systemd session?); it holds the launch lock}"
  exec {lock}>"$XDG_RUNTIME_DIR/claude_tmux_run-$SOCKET.lock" || return 1
  if ! flock -w 60 "$lock"; then
    echo "launch: another launch on the $SOCKET socket has held $XDG_RUNTIME_DIR/claude_tmux_run-$SOCKET.lock for 60 s; see who with: fuser -v $XDG_RUNTIME_DIR/claude_tmux_run-$SOCKET.lock" >&2
    return 1
  fi
  if tm has-session -t "=$name" 2>/dev/null; then
    read -r pane _ < <(claude_pane "=$name")
    pane=${pane:-$(claude_launched "=$name")}
    if [ -n "$pane" ]; then
      echo "launch: session $name already has claude in pane $pane (another launch got there first); not starting a second" >&2
      return 1
    fi
    at=(-t "=$name:0")
    tm list-windows -t "=$name:" -F '#{window_index}' | grep -qx 0 && at=(-b "${at[@]}")
    tm new-window -d "${at[@]}" -P -F '#{pane_id}' \
      -c "$dir" "${PANE_CMD[@]}" "$@" --remote-control
    return
  fi
  if ! tm list-sessions >/dev/null 2>&1; then
    "$(dirname "$0")/../home/.config/tmux/reap-panes.sh" \
      "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCKET" --server-gone || return 1
    scope=(systemd-run --user --scope --quiet --collect
      --unit="tmux-server-$SOCKET"
      --description="tmux server for the $SOCKET socket (claude_tmux_run.sh)")
  fi
  "${scope[@]}" tmux "${TMUX_SERVER[@]}" new-session -d -P -F '#{pane_id}' \
    -s "$name" -c "$dir" "${PANE_CMD[@]}" "$@" --remote-control {lock}>&-
}

# pane_proc <pane>: "<pane_dead> <pane_pid>" of that pane; fails once the
# pane is gone (its process exited and nothing kept it).
pane_proc() { tm display-message -p -t "$1" '#{pane_dead} #{pane_pid}' 2>/dev/null; }

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
    0) echo "session $(tm display-message -p -t "$pane" '#{session_name}'): $what" ;;
    2) echo "pane $pane: $what -- but its login shell has not started claude after 60 s; see what it is stuck on (tmux ${TMUX_SERVER[*]} capture-pane -p -t $pane)" >&2 ;;
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
    # Without a name: the manager, whatever label it carries, and
    # a missing one is fine. With one: the session of exactly that name,
    # killed by "=" -- a bare tmux target prefix-matches, so
    # `kill-session -t api` with no api left kills api2 -- and a bare
    # <name> never reaches a labeled <name>/<task>, which holds a different
    # conversation: `stop api` beside api/login and api/docs
    # kills api or nothing (exact_session).
    if [ $# -lt 2 ]; then
      s=$(sessions_under "$MANAGER") || exit 1
      s=${s%%$'\n'*}
      [ -z "$s" ] && exit 0
    else
      s="$2"
      exact_session stop "$s"
    fi
    tm kill-session -t "=$s" && echo "stopped session $s"
    exit
    ;;
  new)
    # A FRESH conversation, whatever the name owns already (see Naming for
    # why this is not load's job). The cheap refusals come first: the
    # transcript scan reads every transcript's head and tail.
    usage="usage: $0 new <name>[/<task>] <dir> [--dangerous]  (name and task: A-Za-z0-9_- only)"
    parse_args "$usage" 2 "${@:2}"
    spec=${rest[0]} dir=${rest[1]}
    conv="$CONV$spec"
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
        echo "load: no conversation has id ${rest[0]} ($0 history <name> lists them)" >&2
        exit 1
      fi
    else
      parse_args "$usage" 1 "${@:2}"
      spec=${rest[0]}
      if [[ ! "$spec" =~ $NAME_RE ]]; then
        echo "$usage" >&2
        exit 1
      fi
      find_conversation resolve "$CONV$spec" "$HOME"/.claude/projects/*/*.jsonl
      if [ -z "$id" ]; then
        echo "load: no conversation named $CONV$spec; $0 new $spec <dir> starts one ($0 conversations lists what exists)" >&2
        exit 1
      fi
    fi
    # The session a conversation runs in carries its title minus the
    # hostname -- api/docs for <host>/api/docs, whichever spec found it. An
    # id can reach a conversation titled otherwise (by hand), which names no
    # session.
    target=${title#"$CONV"}
    if [ "$target" = "$title" ] || [[ ! "$target" =~ $NAME_RE ]]; then
      named="titled '$title'"
      [ -n "$title" ] || named=untitled
      echo "load: conversation $id is $named, which names no session ($CONV<name>[/<task>]); rename it from the /resume picker (Ctrl+R) first" >&2
      exit 1
    fi

    # One live session per FULL name: api, api/login and api/docs are
    # three names and run side by side; what cannot happen is a second
    # session of one of them. Already up is success when the live session
    # holds what was asked for -- any conversation of a bare name, the
    # labeled one, the very id; switching it would kill work in flight,
    # which is the user's call, not this script's.
    #
    # A live session with no claude in it (it exited beside other windows,
    # see the header) is not "already running": the conversation is resumed
    # into it as window 0. One still starting claude is left to finish.
    under=$(sessions_under "${target%%/*}") || exit 1
    pid=""
    if grep -qxF -e "$target" <<<"$under"; then
      read -r _ pid _ < <(claude_pane "=$target")
      if [ -z "${pid:-}" ] && starting=$(claude_launched "=$target") && [ -n "$starting" ]; then
        echo "session $target: claude is starting (or restarting) in pane $starting; wait for it ($0 status)" >&2
        exit 1
      fi
    fi
    if [ -n "${pid:-}" ]; then
      agents=$(live_agents) || exit 1
      live=$(agent_name "$pid" <<<"$agents")
      if [ -n "$spec" ] && [[ "$spec" != */* ]]; then
        ok=1
      elif [ -n "$spec" ]; then
        ok=$([ "$(canon_title "$live")" = "$title" ] && echo 1)
      else
        ok=$([ "$(agent_id "$pid" <<<"$agents")" = "$id" ] && echo 1)
      fi
      if [ -n "$ok" ]; then
        echo "session $target already running${live:+ ($live)}"
        exit 0
      fi
      echo "session $target is running ${live:-an unknown conversation}, not $title ($id); stop it first ($0 stop $target) or ask for it to finish" >&2
      exit 1
    fi
    if grep -qxF -e "$target" <<<"$under"; then
      echo "session $target is live without claude: resuming its conversation into window 0"
    fi

    if [ "$cwd" = - ]; then
      echo "conversation $title ($id) records no working directory and neither does any transcript beside it; resume it by hand from the right directory" >&2
      exit 1
    fi
    resume_session "$target" "$cwd" "${mode[@]}"
    exit
    ;;
  in-view)
    # What prefix C-r restarts with <pane> in view. "pane" anywhere but on
    # the claude socket, whose every session is one conversation: there
    # "session", its claude wherever in it the user is (nvim in a second
    # window), but for a claude in view it did not launch -- typed at a
    # shell's prompt in a window of the session -- which is "pane".
    if [ $# -ne 3 ]; then
      echo "usage: $0 in-view <tmux socket path> <pane id>" >&2
      exit 1
    fi
    TMUX_SERVER=(-S "$2")
    if [ "${2##*/}" != "$SOCKET" ]; then
      echo pane
      exit 0
    fi
    read -r pane_pid start < <(tm display-message -p -t "$3" '#{pane_pid} #{pane_start_command}' 2>/dev/null)
    if [ -n "$(fg_claude "${pane_pid:-0}")" ] && [[ "${start:-}" != *"$PANE_MARK"* ]]; then
      echo pane
    else
      echo session
    fi
    exit 0
    ;;
  restart)
    # A fresh claude on the same conversation, in place: what a Claude Code
    # update needs. stop + load does it too, but destroys the session, so
    # every client attached to it detaches (or jumps to another session) and
    # has to be pointed back. Here the pane survives. The claude to restart:
    #
    #   restart <name>                    the claude of that session on the
    #                                     claude socket (window 0's)
    #   restart --pane <socket> <pane>    the claude in the foreground of
    #                                     that pane, on any tmux server (a
    #                                     Mac's default one): what prefix C-r
    #                                     passes for the pane in view
    #
    # and the pane's shape, which decides how it comes back:
    #
    #   respawn  claude IS the pane's process, launched here (PANE_CMD), as
    #            every claude socket session's is. tmux respawns the pane
    #            from a pane-died hook armed before the kill:
    #
    #   checks   all before the kill; a refusal leaves claude running
    #   arm      this pane only: remain-on-exit on, pane-died hook
    #   TERM --> claude exits, however long its shutdown takes
    #            hook (tmux): respawn-pane PANE_CMD --resume <id> -n <title>
    #            <mode>, then unset the hook and remain-on-exit
    #   wait     for the respawn; a claude still up after EXIT_SECONDS gets KILL
    #   stop     the old claude's scope: the new one runs in a scope of its
    #            own, and what the old one left detached there ends now
    #   report   wait_alive on the new claude
    #
    #            The respawn and the disarm are one command list the server
    #            runs, so once TERM is sent the restart completes and the
    #            pane ends up as before whatever happens to this script:
    #            interrupted (Esc on the manager's Bash call), killed, or
    #            timed out waiting on a slow shutdown.
    #
    #   shell    claude runs in the foreground of an interactive shell, as
    #            one typed at its prompt does. The shell stays -- claude was
    #            started from it, with its environment (a venv, an export) --
    #            and the resume is typed at its prompt, as the user would:
    #
    #   checks   as above, and: its parent is a shell, in the directory of
    #            the conversation (where `claude --resume <id>` finds it)
    #   TERM --> claude exits; still up after EXIT_SECONDS: KILL
    #   wait     for the shell to take the terminal back (its prompt)
    #   type     claude --resume <id> [-n <name>] <mode>, Enter
    #   report   a claude in the pane's foreground again, up ALIVE_SECONDS,
    #            and among agents --json, on the conversation or a new id
    #
    #            -n only for a conversation that has a custom title: on
    #            any other, the auto-generated name agents --json shows would
    #            become one, for good, in place of its AI title. The mode is
    #            the one the conversation was last in, from its
    #            transcript (a prompt records it, Shift-Tab changes too);
    #            other flags it was started with (--model, --add-dir) are
    #            not carried, as macOS's ps cannot give a process's argv back
    #            word for word. Nothing types the resume should this script
    #            die after the TERM: the log holds the command, and C-r runs
    #            it under tmux's run-shell, out of reach of claude's Esc. The
    #            pane's scope holds the shell, so nothing is stopped: what the
    #            old claude detached stays, as after a quit by hand.
    #
    # Refused unless --force: work a restart would kill -- a turn, or a
    # background shell claude tracks (bg_shells) -- read just before
    # arming. agents --json cannot tell the two apart: it reports "busy"
    # for as long as a background shell runs, the turn long over (2.1.303),
    # but the pane shows which, so the call is the user's. --check runs
    # every check, kills nothing, and prints that work, one item per line,
    # instead of refusing over it: what prefix C-r puts in its popup
    # (~/.dotfiles/home/.config/tmux/restart-claude.sh) before a forced
    # restart. Detached processes the old claude left (detached) are listed
    # with that work but never refuse: a reload ends them by design, as
    # closing the session would (home/.config/tmux/reap-panes.sh), and a job
    # meant to outlive both runs as its own unit (systemd-run --user
    # --unit=<name>). Always refused: a conversation also open in another
    # process (two writers corrupt one transcript), and a respawn pane not
    # launched here, whose start command names no permission mode to keep
    # (auto, or bypass for --dangerous).
    # The directory is the conversation's own, from its transcript
    # (find_conversation), not claude's cwd, which EnterWorktree moves.
    usage="usage: $0 restart [--check|--force] <name>[/<task>]  (the exact session name, as status prints it)
   or: $0 restart [--check|--force] --pane <tmux socket path> <pane id>  (%N, as #{pane_id} prints it)"
    check="" force="" by_pane="" operands=()
    for a in "${@:2}"; do
      case "$a" in
        --check) check=1 ;;
        --force) force=1 ;;
        --pane) by_pane=1 ;;
        *) operands+=("$a") ;;
      esac
    done
    want=1
    [ -z "$by_pane" ] || want=2
    if [ "${#operands[@]}" -ne "$want" ] || { [ -n "$by_pane" ] && [[ ! "${operands[1]}" =~ ^%[0-9]+$ ]]; }; then
      echo "$usage" >&2
      exit 1
    fi

    # The pane and the claude in it ($where names them in every message).
    # --pane: the claude in the pane's foreground (fg_claude): the pane's
    # own process (respawn), or a job of the shell in it (shell).
    if [ -n "$by_pane" ]; then
      TMUX_SERVER=(-S "${operands[0]}")
      pane=${operands[1]}
      if ! read -r pane_pid s < <(tm display-message -p -t "$pane" '#{pane_pid} #{session_name}' 2>/dev/null) \
        || [ -z "${pane_pid:-}" ]; then
        echo "restart: no pane $pane on the tmux server at ${operands[0]}" >&2
        exit 1
      fi
      where="pane $pane ($s)"
      agents=$(live_agents) || exit 1
      pid=$(fg_claude "$pane_pid")
      if [ -z "$pid" ]; then
        if [[ "$(tm display-message -p -t "$pane" '#{pane_start_command}')" == *"$PANE_MARK"* ]]; then
          echo "restart: claude is starting (or restarting) in $where; wait for it ($0 status)" >&2
        else
          echo "restart: no claude in the foreground of $where, so nothing to restart" >&2
        fi
        exit 1
      fi
      if [ "$pid" = "$pane_pid" ]; then shape=respawn; else shape=shell; fi
    else
      s=${operands[0]}
      exact_session restart "$s"
      read -r pane pid _ < <(claude_pane "=$s")
      if [ -z "${pane:-}" ]; then
        if starting=$(claude_launched "=$s") && [ -n "$starting" ]; then
          echo "restart: claude is starting (or restarting) in pane $starting of session $s; wait for it ($0 status)" >&2
        else
          echo "restart: no claude running in session $s, so nothing to restart; $0 load $s resumes its conversation into it" >&2
        fi
        exit 1
      fi
      where="session $s"
      agents=$(live_agents) || exit 1
      shape=respawn
    fi

    # The conversation that claude has open.
    live_id=$(agent_id "$pid" <<<"$agents")
    live_title=$(agent_name "$pid" <<<"$agents")
    if [ -z "$live_id" ]; then
      echo "restart: claude $pid in $where is not among 'claude agents --json'; cannot tell which conversation to resume" >&2
      exit 1
    fi
    if awk -F'\t' -v pid="$pid" -v id="$live_id" '$2 == id && $1 != pid { f = 1 } END { exit !f }' <<<"$agents"; then
      echo "restart: conversation $live_title ($live_id) is also open in another claude process; close that one first" >&2
      exit 1
    fi
    find_conversation resolve-id "$live_id" "$HOME"/.claude/projects/*/*.jsonl
    if [ -z "$id" ] || [ "$cwd" = - ]; then
      echo "restart: no transcript with a directory holds conversation $live_id (claude $pid in $where); left running" >&2
      exit 1
    fi

    # What the new claude is started with, per shape.
    if [ "$shape" = respawn ]; then
      login_shell_ok || exit 1
      start=$(tm display-message -p -t "$pane" '#{pane_start_command}') || exit 1
      case " $start " in
        *" --dangerously-skip-permissions "*) mode=(--dangerously-skip-permissions) ;;
        *" --permission-mode auto "*) mode=(--permission-mode auto) ;;
        *)
          echo "restart: $where was not started by $0 (its pane runs: $start); restart it by hand" >&2
          exit 1
          ;;
      esac
    else
      # The shell claude was typed at: its parent, which must be a shell
      # shell_words can quote for, and must hold the terminal again once
      # claude is gone (host_pgid). A login shell's comm is "-fish".
      host=$(ps -o ppid= -p "$pid" | tr -d ' ')
      host_pgid=$(ps -o pgid= -p "$host" | tr -d ' ')
      sh_name=$(ps -o comm= -p "$host")
      sh_name=${sh_name##*/} sh_name=${sh_name#-}
      case $sh_name in
        fish | bash | zsh | sh | dash | ksh) ;;
        *)
          echo "restart: claude $pid in $where runs under ${sh_name:-nothing} (pid $host), not a shell to type the resume at; restart it by hand" >&2
          exit 1
          ;;
      esac
      case $pmode in
        bypassPermissions) mode=(--dangerously-skip-permissions) ;;
        default | acceptEdits | plan | auto | dontAsk) mode=(--permission-mode "$pmode") ;;
        *)
          echo "restart: conversation $live_id records no permission mode claude takes ('$pmode', in its transcript); restart it by hand" >&2
          exit 1
          ;;
      esac
      # `claude --resume <id>` finds a conversation only from its own
      # directory: /tmp/x and /private/tmp/x are one on a Mac, hence -P.
      # A directory since removed resolves to nothing, on either side.
      here=$(cwd_of "$host")
      real_here=$(cd "$here" 2>/dev/null && pwd -P)
      real_cwd=$(cd "$cwd" 2>/dev/null && pwd -P)
      if [ -z "$real_here" ] || [ "$real_here" != "$real_cwd" ]; then
        echo "restart: the $sh_name claude $pid runs under is in ${here:-a directory it cannot read}, but conversation $live_id belongs to $cwd, where claude --resume has to run; restart it by hand" >&2
        exit 1
      fi
      resume=(claude --resume "$live_id")
      [ -z "$title" ] || resume+=(-n "$(canon_title "$live_title")")
      typed=$(shell_words "$sh_name" "${resume[@]}" "${mode[@]}")
    fi

    # idle_check: what a restart would kill, as one line in "work" --
    #   busy: a turn, or 1 background shell(s): sleep 900
    # -- empty when claude is idle with no shells. Refused unless --force.
    # --check prints it, and what the old scope holds detached ("gone"),
    # one item per line instead, what prefix C-r's popup lists:
    #   busy: a turn
    #   background shell: sleep 900
    #   detached: /usr/bin/ssh
    #   detached: /usr/bin/busybox (tail)
    # (detached ones by program, see program; their full command lines go
    # to the log).
    # Asked after the slow transcript lookup, so that little can start
    # between it and the arming (a remote-control message could start a turn).
    # The old scope only for respawn: a shell's claude shares its pane's
    # scope with the shell, which stays, so what is detached there stays too.
    old_scope=""
    [ "$shape" != respawn ] || old_scope=$(scope_of "$pid")
    case $old_scope in tmux-spawn-*.scope) ;; *) old_scope="" ;; esac
    idle_check() {
      local state shells left programs
      agents=$(live_agents) || exit 1
      state=$(agent_status "$pid" <<<"$agents")
      shells=$(bg_shells "$pid")
      work=""
      [ "$state" = idle ] || work="$state: a turn"
      if [ -n "$shells" ]; then
        work+="${work:+, or }$(wc -l <<<"$shells" | tr -d ' ') background shell(s): $(cut -d' ' -f2- <<<"$shells" | paste -sd ';' -)"
      fi
      gone=""
      [ -z "$old_scope" ] || left=$(detached "$old_scope" "$pid")
      if [ -n "${left:-}" ]; then
        programs=$(while read -r p _; do program "$p"; done <<<"$left")
        gone="$(wc -l <<<"$left" | tr -d ' ') detached process(es): $(paste -sd ';' - <<<"$programs")"
      fi
      if [ -n "$check" ]; then
        [ "$state" = idle ] || echo "$state: a turn"
        [ -z "$shells" ] || cut -d' ' -f2- <<<"$shells" | sed 's/^/background shell: /'
        [ -z "$gone" ] || sed 's/^/detached: /' <<<"$programs"
      elif [ -n "$work" ] && [ -z "$force" ]; then
        echo "restart: $where is not idle ($work), which a restart kills; wait for it (Esc ends a turn), or --force" >&2
        exit 1
      fi
    }
    idle_check
    [ -z "$check" ] || exit 0

    # From here on every step is logged, the log's path printed first.
    . "$(dirname "$0")/lib/event_log.sh"
    event_log_start claude_tmux_restart || exit 1
    echo "log: $EVENT_LOG_FILE"
    say() { log "$where: $*"; }
    die() {
      log "$where: FAILED $*" >&2
      exit 1
    }
    say "claude $pid, conversation $live_id ($live_title), dir $cwd, ${mode[*]}${work:+; forced over $work}${gone:+; ending $gone}"

    # shell: TERM, wait for the prompt, type the resume (see the top).
    if [ "$shape" = shell ]; then
      say "once it exits, typing at the prompt of $sh_name $host: $typed"
      kill -TERM "$pid" || say "TERM to claude $pid failed: it already exited"
      say "sent TERM to claude $pid"
      # exited <seconds>: whether claude is gone within that long.
      exited() {
        local i
        for ((i = 0; i < $1 * 4; i++)); do
          kill -0 "$pid" 2>/dev/null || return 0
          sleep 0.25
        done
        return 1
      }
      if ! exited "$EXIT_SECONDS"; then
        say "claude $pid still up $EXIT_SECONDS s after TERM; sending KILL"
        kill -KILL "$pid"
        exited 5 || die "claude $pid survived KILL; nothing typed. Once it exits, type there: $typed"
      fi

      # The shell back at its prompt: its process group holds the terminal.
      for ((i = 0; ; i++)); do
        kill -0 "$host" 2>/dev/null || die "$sh_name $host exited with claude; nothing typed"
        [ "$(ps -o tpgid= -p "$host" | tr -d ' ')" = "$host_pgid" ] && break
        [ "$i" -lt 40 ] || die "$sh_name $host has not taken the terminal back 10 s after claude exited; nothing typed. Type there: $typed"
        sleep 0.25
      done
      # Scrolled back, the pane is in copy mode, where these keys would be
      # commands: one opens a prompt, which holds send-keys for good.
      if [ "$(tm display-message -p -t "$pane" '#{pane_in_mode}')" = 1 ]; then
        tm send-keys -t "$pane" -X cancel
        [ "$(tm display-message -p -t "$pane" '#{pane_in_mode}')" = 0 ] \
          || die "$where stays in a mode tmux would not leave; nothing typed. Type there: $typed"
        say "left copy mode"
      fi
      if ! tm send-keys -t "$pane" -l -- "$typed" || ! tm send-keys -t "$pane" Enter; then
        die "could not type into $where (gone?); type there: $typed"
      fi
      say "typed the resume"

      # The new claude: the shell's next foreground job, a claude (comm is
      # a full path on macOS), up through the startup window -- which a
      # claude refusing the resume ("No conversation found") exits within --
      # and then among agents --json. Under any id: a resume can continue
      # in a new transcript (see ../claude_tmux_session/AGENTS.md).
      new=""
      for ((i = 0; ; i++)); do
        f=$(ps -o tpgid= -p "$host" | tr -d ' ')
        c=$(ps -o comm= -p "${f:-0}" 2>/dev/null)
        if [ -n "$f" ] && [ "$f" != "$host_pgid" ] && [ "$f" != "$pid" ] && [ "${c##*/}" = claude ]; then
          new=$f
          break
        fi
        [ "$i" -lt 240 ] || die "no claude in the foreground of $where 60 s after typing the resume; see the pane"
        sleep 0.25
      done
      for ((i = 0; i < ALIVE_SECONDS; i++)); do
        sleep 1
        kill -0 "$new" 2>/dev/null || die "claude $new exited during startup; see the pane"
      done
      for ((i = 0; ; i++)); do
        agents=$(live_agents) || die "cannot tell whether claude $new resumed $live_id"
        new_id=$(agent_id "$new" <<<"$agents")
        [ -n "$new_id" ] && break
        [ "$i" -lt 30 ] || die "claude $new is up, but not among agents --json 30 s on; see the pane"
        sleep 1
      done
      [ "$new_id" = "$live_id" ] || say "the resume continues under id $new_id"
      log "$where: restarted conversation $live_id ($live_title) in $cwd (${mode[*]})"
      exit 0
    fi

    # Arm. Until TERM goes out a signal disarms, so an interrupted restart
    # leaves no hook behind to resume a claude that exits later on its own.
    disarm() {
      tm set-hook -p -u -t "$pane" pane-died
      tm set-option -p -u -t "$pane" remain-on-exit
    }
    trap 'disarm; die "interrupted before the kill; claude $pid left running"' INT TERM HUP
    hook="respawn-pane -t $pane -c $(tmux_quote "$cwd") $(tmux_quote "${PANE_CMD[@]}" \
      --resume "$live_id" -n "$(canon_title "$live_title")" "${mode[@]}" --remote-control)"
    hook+=" ; set-hook -p -u -t $pane pane-died ; set-option -p -u -t $pane remain-on-exit"
    if ! tm set-option -p -t "$pane" remain-on-exit on \
      || ! tm set-hook -p -t "$pane" pane-died "$hook"; then
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
    say "respawned: pane $pane runs pid ${state#* }"

    # The old claude's scope: the new one must run in another (tmux >= 3.7
    # makes one per spawn), else stopping it would end the new claude too.
    # What is left there -- jobs the old claude detached, shells --force
    # orphaned -- ends now. Should this script die before here, the next
    # session to close stops the scope all the same (reap-panes.sh: it
    # holds no live pane's own process).
    if [ -n "$old_scope" ]; then
      [ "$(scope_of "${state#* }")" != "$old_scope" ] \
        || die "the new claude runs in the old one's scope $old_scope; it was left running"
      if [ "$(systemctl --user show -p LoadState --value "$old_scope")" = loaded ]; then
        left=$(detached "$old_scope" | paste -sd ';' -)
        if systemctl --user stop "$old_scope" 2>/dev/null; then
          say "stopped $old_scope, the old claude's scope: ${left:-empty}"
        elif [ "$(systemctl --user show -p LoadState --value "$old_scope")" = loaded ]; then
          die "could not stop $old_scope (holding: ${left:-nothing listed}); see: systemctl --user status $old_scope"
        fi
      fi
    fi
    say "waiting for claude"
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
    names=$(tm list-sessions -F '#{session_name}' 2>/dev/null | sort)
    if [ -z "$names" ]; then
      echo "no sessions on tmux socket $SOCKET"
      exit 0
    fi
    agents=$(live_agents) || exit 1
    for s in $names; do
      # The claude pane wherever it is; with none, the session's first pane
      # (the one it was created with) shows what runs instead.
      pane=$(claude_pane "=$s")
      [ -n "$pane" ] || pane=$(tm list-panes -s -t "=$s:" \
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
      tm capture-pane -p -t "$pane_id" 2>/dev/null \
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
    live=$(cut -f3 <<<"$live" | canon_titles)
    printf '%-40s %-5s %-17s %s\n' NAME LIVE 'LAST ACTIVE' DIRECTORY
    transcripts tsv "" "$HOME"/.claude/projects/*/*.jsonl \
      | while IFS=$'\t' read -r ts _ title cwd _; do
        name=${title#"$CONV"}
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
    transcripts history "$CONV$name" "$HOME"/.claude/projects/*/*.jsonl
    exit 0
    ;;
  start)
    # ExecStart, at boot: the manager's session unless it exists, under
    # whatever label its conversation carries (manager, manager/<task>).
    # Nothing watches it after: a manager that quits or crashes stays down
    # until the next boot, `systemctl --user start claude-tmux` once its
    # session is gone (another window may keep it alive), or
    # `load manager --dangerous`, which also resumes it into a live session.
    #
    #   no session          -> started: the conversation resumed, or a new one
    #   session, any state  -> left alone
    #
    # A tmux failure is its error, not "no session": nothing is launched on
    # a guess, and the unit fails with it.
    if [ $# -ne 1 ]; then
      echo "usage: $0 start  (claude-tmux.service's ExecStart; takes no arguments)" >&2
      exit 1
    fi
    s=$(find_session "$MANAGER") || exit 1
    if [ -n "$s" ]; then
      echo "manager session $s exists; leaving it (whether claude runs in it: $0 status; bring claude back into it: $0 load manager --dangerous)"
      exit 0
    fi
    find_conversation resolve "$CONV$MANAGER" \
      "$HOME/.claude/projects/${MANAGER_DIR//[^a-zA-Z0-9]/-}"/*.jsonl
    if [ -n "$id" ]; then
      resume_session "$MANAGER" "$MANAGER_DIR" --dangerously-skip-permissions || exit 1
    else
      start_session "$MANAGER" "$MANAGER_DIR" "new conversation $CONV$MANAGER in $MANAGER_DIR" \
        -n "$CONV$MANAGER" --dangerously-skip-permissions || exit 1
    fi
    exit 0
    ;;
  *)
    {
      echo "usage: $0 start|new|load|restart|stop|status|conversations|history ...  (got '${1:-}'; the header of $0 lists each one's arguments)"
      # The unit ran this bare, then as serve (a watch loop), before start;
      # systemd keeps a unit as it last read it.
      case ${1:-} in
        "" | serve) echo "  claude-tmux.service runs '$0 start'; a unit calling it '${1:-}' was loaded before that: systemctl --user daemon-reload && systemctl --user restart claude-tmux" ;;
      esac
    } >&2
    exit 1
    ;;
esac

# /// script
# requires-python = ">=3.11"
# dependencies = ["iterm2==2.25"]
# ///
r"""The logic behind scripts/iterm2_ssh_arrangement.sh, on iTerm2's Python API.

Save the tabs of iTerm2's windows as the commands that bring each back, and
restore them into new windows. A tab saved here can be reopened after iTerm2
lost it: a reboot, a Cmd-Q, or an upgrade without session restoration.

  save [<name>]                 every window (<name> defaults to "all")
  save <name> <title prefix>    the one window whose title starts so
  snapshot                      every window, as "auto-<UTC YYYYMMDD_HHMMSS>",
                                then all but the newest 144 (a day) removed;
                                run every 10 minutes by Hammerspoon
                                (home/.hammerspoon/iterm2_snapshots.lua)
    iTerm2 (Python API) --> per window, the key window first: its title
                            template, and per tab: panes, jobName,
                            commandLine, title, path, hostname (read_windows)
      |
      v  plan(): what each tab is
    ssh, title "[<shown>]"   -> remote tmux; which socket holds the session
                                shown, and under what name, is asked of the
                                host (one ssh per host)
                                -> LC_TMUX_ATTACH=claude:<session> \
                                     ssh -o SendEnv=LC_TMUX_ATTACH <login>
    ssh, any other title     -> the far side's directory, if it reported one
                                -> LC_LOGIN_DIR=<dir, %-encoded> \
                                     ssh -o SendEnv=LC_LOGIN_DIR <login>
                                else -> ssh <login>
    anything else            -> cd '<path>' (a local tab; its program is
                                not rerun)
      |
      v
    ~/.local/state/iterm2_ssh_arrangements/<name>.txt: plain text, to read
    or edit by hand; a "window: <title template>" line per window, then one
    command per tab, in tab order (render / parse_file)

  restore [<name>]
    the file --> a new window per "window:" block, a tab per line, each line
                 typed into the tab's shell (as Cmd-T does), so exiting ssh
                 leaves a local shell; its title template set and read back.
                 The first block's window ends up in front, as it was saved.
                 Then each tmux tab is waited on until its title shows its
                 session, and each directory tab until its path is that
                 directory (wait_landed): a request the far side never acted
                 on leaves a plain shell in ~, which fails the restore by name.
                 It adds to the windows already open, and runs from any
                 terminal while iTerm2 runs.

  relaunch [<name>]
    restore, onto an iTerm2 that holds nothing else; run from another
    terminal app, since it quits iTerm2 (relaunch):

      parse the file              a bad one fails here, before anything closes
      refuse under iTerm2         its quit would end this run halfway
      close every window          so the quit asks no "Quit iTerm2?" and
                                  leaves no windows to restore at launch;
                                  in a child process (CLOSE_TIMEOUT)
      quit iTerm2, wait it out    (skipped when it is not running)
      launch it, connect          once its API answers (RELAUNCH_TIMEOUT)
      restore                     as above
      close every other window    what iTerm2 opened at launch
                                  (AlwaysOpenWindowAtStartup)

<login> is ssh_command.py's replay of the tab's ssh command line (Cmd-T's
parser): the options and destination, never a remote command or forward.
The "[<shown>]" title is ~/.tmux.conf's set-titles-string for an iTerm2
client: the session name on the default socket, and on claude_tmux_run.sh's
"claude" one the conversation's full name, "<hostname>/<session>" (TITLED).
The title does not say which socket, hence the lookup, which also maps
the shown name back to the session to attach:

    "[main]"             -> default:main
    "[vm/api/docs]"      -> claude:api/docs   (host "vm")

The attach goes through the remote login shell, not a remote command: over
Tailscale SSH a remote command gets a pty that stays root's, and the
client-attached hook (home/.config/tmux/report-attach.sh) cannot write the
iTerm2 host report to it. A plain login runs login(1), which hands the pty
to the user; the login fish then attaches what LC_TMUX_ATTACH names
(home/.config/fish/functions/tmux_attach_requested.fish):

    ssh -t vm tmux -L claude attach -t =x                   pty root's,
                                                            report fails
    LC_TMUX_ATTACH=claude:x ssh -o SendEnv=LC_TMUX_ATTACH vm
                                                            pty the user's,
                                                            report lands

SendEnv, not SetEnv: ssh keeps only the first SetEnv it reads, so one on
the command line would drop the host's own from ~/.ssh/config, while
SendEnv lines add up. A directory goes the same way, for the same reason,
and the login fish cd's into what LC_LOGIN_DIR names
(home/.config/fish/functions/login_dir_requested.fish). Both values are
%-encoded alike (send_line), "/" too, and decoded alike on the far side
(__ssh_arrangement_decode.fish).

An ssh tab's path is the far side's directory only once the far side has
said so: fish's prompt sends it (OSC 7) after iterm2_report_host has named
the remote host. A far side that reports nothing (a host without these
dotfiles) leaves the tab on the local host to iTerm2, its path the local
one of ssh, so such a tab is saved as its login alone. The local host is
told by the session the save runs in (ITERM_SESSION_ID): iTerm2 names this
Mac "<LocalHostName>.local" in a session, which is neither gethostname()
nor its own localhostName variable, so it is read, not guessed. Inside tmux
that variable is the tab's that started the tmux session, maybe gone or
since ssh'd elsewhere, so there the script refuses (local_host). A snapshot
runs in no tab, and reads the names off the local tabs instead (local_hosts).
A restore reads it off each tab it opens, before typing into it (fresh_host):
a new tab runs the local shell even beside an ssh one, so a restore needs
no tab of its own, and runs from tmux or another terminal app.

A reported directory is still asked of the login's host before it is
saved (one ssh per host, as for tmux): a tab that ssh'd on from there
reports the next host's directory, and saving it would fail the restore.

Lines typed into a tab are for fish, the shell of the default profile.
Imported without running (scripts/tests/iterm2_ssh_arrangement_test.py) it
only defines its functions.
"""

# A script beside its shell wrapper, no license header, as in scripts/tests.
# ruff: noqa: CPY001

import asyncio
import multiprocessing
import os
import re
import subprocess
import sys
import time
from collections.abc import Awaitable, Callable, Generator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import quote, unquote

import iterm2
import websockets.exceptions

# The parser lives beside its first user, Cmd-T's iterm2_api.py.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "home/.hammerspoon"))
import ssh_command

SOCKETS = ("claude", "default")  # tmux_attach_requested.fish accepts these
# What each socket's sessions show inside the brackets of the terminal title,
# as tmux formats; must match ~/.tmux.conf's set-titles-string.
TITLED = {"claude": "#{host}/#{session_name}", "default": "#{session_name}"}
SESSION_FIELDS = 3  # a list_sessions_argv line: socket, session, shown name
LANDING_TIMEOUT = 30.0  # s for every restored tab to show its session or directory
FRESH_HOST_TIMEOUT = 5.0  # s for a new tab to report its host (it takes ~0.1)
# s for a quit iTerm2 to exit, and for a launched one to answer its API
# (longer the first time, while macOS asks to let this terminal control it).
RELAUNCH_TIMEOUT = 120
CLOSE_TIMEOUT = 30  # s for relaunch's child to close every window (it takes ~1)
PROGRESS_EVERY = 5.0  # s between the lines a relaunch logs while it waits
ITERM2_BUNDLE = "com.googlecode.iterm2"
DIR = Path.home() / ".local/state/iterm2_ssh_arrangements"
SNAPSHOT_PREFIX = "auto-"  # snapshot "auto-20261019_143000", a UTC time
# A day of them at Hammerspoon's one per 10 minutes (iterm2_snapshots.lua).
SNAPSHOT_KEEP = 144
# What a snapshot's ssh may not do: ask for anything (no tty to answer on)
# or wait out a host that is down for the TCP timeout.
UNATTENDED_SSH = ("-o", "BatchMode=yes", "-o", "ConnectTimeout=10")
USAGE = (
    "usage: iterm2_ssh_arrangement.sh save [<name> [<window title prefix>]]"
    " | restore [<name>] | relaunch [<name>] | snapshot"
)
MAX_ARGS = 3  # save <name> <prefix>
LOG: list[Path] = []  # the run's event log, set by main()
# What read_windows asks of a tab's first pane, in Tab's field order.
TAB_VARIABLES = ("jobName", "commandLine", "name", "path", "hostname")


class ArrangementError(Exception):
    """A save or restore that would leave the wrong thing; the message says what."""


@dataclass
class Tab:
    """What iTerm2 reports of one tab, by its first pane."""

    panes: int
    job: str
    command_line: str
    title: str
    path: str
    host: str  # iTerm2's hostname: the last one reported in the tab


@dataclass
class Plan:
    """What a tab is, before any remote lookup.

    kind "tmux": login and session; "ssh": login, and the far side's
    directory ("" where it reported none, which `note` says); "local": line.
    """

    kind: str
    login: str = ""
    session: str = ""
    line: str = ""
    path: str = ""
    note: str = ""


@dataclass
class Saved:
    """A window as the file holds it: its title template and a line per tab."""

    template: str
    lines: list[str]


def render(name: str, saved_at: str, windows: list[Saved]) -> str:
    """Return the file's text for `windows`."""
    out = [
        f'# iTerm2 ssh arrangement "{name}", saved {saved_at}; restore with:',
        f"#   ~/.dotfiles/scripts/iterm2_ssh_arrangement.sh restore {name}",
        "# Each window: its title template (Window > Edit Window Title takes it",
        "# as is), then one command per tab. The first window is restored in front.",
    ]
    for w in windows:
        out += ["", f"window: {w.template}".rstrip(" "), *w.lines]
    return "\n".join(out) + "\n"


def parse_file(text: str) -> list[Saved]:
    r"""Return the windows of the file's text.

    "window: x\nssh vm\n" -> [Saved("x", ["ssh vm"])]. A command before the
    first "window:" line, a window with no tabs, or an attach line no
    restore can land (attach_request) is an error: a hand edit gone wrong,
    caught here so that no tab opens before it.
    """
    windows: list[tuple[int, Saved]] = []
    for n, line in enumerate(text.splitlines(), 1):
        if m := re.fullmatch(r"window: ?(.*)", line):
            windows.append((n, Saved(m[1], [])))
        elif line and not line.startswith("#"):
            if not windows:
                msg = f'line {n} is a command before any "window:" line: {line}'
                raise ArrangementError(msg)
            try:
                attach_request(line)
            except ArrangementError as e:
                msg = f"line {n} {e}"
                raise ArrangementError(msg) from e
            windows[-1][1].lines.append(line)
    if not windows:
        msg = 'no "window:" line'
        raise ArrangementError(msg)
    for i, (n, w) in enumerate(windows, 1):
        if not w.lines:
            msg = f"window {i} (line {n}) has no tabs"
            raise ArrangementError(msg)
    return [w for _, w in windows]


def tmux_session(title: str) -> str | None:
    """Return the name a tab title shows for its remote tmux session, or None.

    "[vm/api/docs]" -> "vm/api/docs"; "[main] " -> "main" (retitle.sh
    may leave a trailing space); "fish:~" -> None. On the claude socket that
    name is "<hostname>/<session>" (TITLED); the lookup maps it back.
    """
    m = re.fullmatch(r"\[(.+)\] ?", title)
    return m[1] if m else None


def tmux(socket: str) -> str:
    """Return the tmux command for `socket`: "tmux" or "tmux -L claude"."""
    return "tmux" if socket == "default" else f"tmux -L {socket}"


def attach_line(login: str, socket: str, session: str) -> str:
    """Return the line that reattaches `session` on `socket`, via the login shell.

    ("ssh -p 2222 vm", "claude", "ai-agent")
        -> "LC_TMUX_ATTACH=claude:ai-agent ssh -o SendEnv=LC_TMUX_ATTACH -p 2222 vm"
    The value is "<socket>:<session>", split at the first ":" on the far
    side; tmux allows no ":" in a session name. LC_ because the stock
    AcceptEnv of sshd (LANG LC_*) passes only those.

    "/" goes as "%2F": Tailscale SSH (1.102) drops a variable whose value
    holds a "/", so "claude:api/docs" never arrived, while every other
    character a plain session name may hold passes. A plain name holds no
    "%", so tmux_attach_requested.fish decodes it unambiguously:
        "api/docs" -> "LC_TMUX_ATTACH=claude:api%2Fdocs ..."
    """
    if not ssh_command.plain(session):
        msg = f"tmux session {session!r} has characters needing quotes; rename it"
        raise ArrangementError(msg)
    return send_line(login, "LC_TMUX_ATTACH", f"{socket}:{session}")


def dir_line(login: str, path: str) -> str:
    """Return the line that logs in and lands in `path` on the far side.

    ("ssh vm", "/home/me/it's here")
        -> "LC_LOGIN_DIR=%2Fhome%2Fme%2Fit%27s%20here ssh -o SendEnv=LC_LOGIN_DIR vm"
    """
    return send_line(login, "LC_LOGIN_DIR", path)


def send_line(login: str, variable: str, value: str) -> str:
    """Return `login` sending `variable`=`value` to the far side's login shell.

    ("ssh -p 2222 vm", "LC_X", "a/b c")
        -> "LC_X=a%2Fb%20c ssh -o SendEnv=LC_X -p 2222 vm"
    Every byte but [A-Za-z0-9_.~:-] is %-encoded: the "/" for Tailscale SSH
    (attach_line), the rest so the value needs no quoting in fish. ":" stays,
    so a tmux line reads as before ("claude:api%2Fdocs"). The far side
    decodes it with `string unescape --style=url` (__ssh_arrangement_decode).
    """
    first, *rest = login.split()
    words = [f"{variable}={quote(value, safe=':')}", first, f"-o SendEnv={variable}"]
    return " ".join([*words, *rest])


def sent_value(line: str, variable: str) -> str | None:
    """Return the value send_line put in `line` for `variable`, decoded; else None.

    ("LC_X=a%2Fb ssh -o SendEnv=LC_X vm", "LC_X") -> "a/b"
    ("ssh vm", "LC_X") -> None
    """
    v = re.escape(variable)
    m = re.fullmatch(rf"{v}=(\S+) \S+ -o SendEnv={v} .+", line)
    return unquote(m[1]) if m else None


def attach_request(line: str) -> tuple[str, str] | None:
    """Return the (socket, session) a saved line asks the far side to attach.

    attach_line's output -> its socket and session; any other line -> None.
    "LC_TMUX_ATTACH=claude:api%2Fdocs ssh -o SendEnv=LC_TMUX_ATTACH vm"
        -> ("claude", "api/docs")
    An attach line no restore can land -- a socket not in SOCKETS, no
    session -- is an error (a hand edit, or a file older than this script).
    """
    value = sent_value(line, "LC_TMUX_ATTACH")
    if value is None:
        return None
    socket, _, session = value.partition(":")
    if socket not in SOCKETS:
        msg = (
            f"attaches on tmux socket {socket!r},"
            f" not one of {', '.join(SOCKETS)}: {line}"
        )
        raise ArrangementError(msg)
    if not session:
        msg = f"attaches no session on socket {socket!r}: {line}"
        raise ArrangementError(msg)
    return socket, session


def dir_request(line: str) -> str | None:
    """Return the directory a saved line asks the far side to land in.

    dir_line's output -> its directory; any other line -> None.
    "LC_LOGIN_DIR=%2Fhome%2Fme ssh -o SendEnv=LC_LOGIN_DIR vm" -> "/home/me"
    """
    return sent_value(line, "LC_LOGIN_DIR")


def fish_quote(s: str) -> str:
    r"""Quote `s` for fish: inside '...' only \ and ' are special."""
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def plan(tab: Tab, index: int, local_hosts: frozenset[str]) -> Plan:
    """Return what tab number `index` is; `local_hosts` are iTerm2's names for this Mac.

    A split tab or an ssh line ssh_command.py will not re-parse is an error:
    saving it as something else would restore the wrong thing.
    """
    if tab.panes != 1:
        msg = f"tab {index} has {tab.panes} panes; only one-pane tabs can be saved"
        raise ArrangementError(msg)
    if tab.job != "ssh":
        if not tab.path:
            msg = f"tab {index}: iTerm2 reports no directory for it"
            raise ArrangementError(msg)
        return Plan("local", line=f"cd {fish_quote(tab.path)}")
    try:
        login = ssh_command.interactive(tab.command_line)
    except ssh_command.NotReplayableError as e:
        msg = f"tab {index}: ssh command line cannot be replayed: {e}"
        raise ArrangementError(msg) from e
    if session := tmux_session(tab.title):
        return Plan("tmux", login=login, session=session)

    # A plain ssh tab lands where its far side last reported being (module
    # docstring); one still on the local host to iTerm2 reported nothing,
    # and its path is ssh's local one.
    #   host "vm", path "/home/me/d"   -> login and "/home/me/d"
    #   host local, path "/Users/me"   -> login alone, and a note saying so
    if tab.host in local_hosts:
        note = (
            f"tab {index}: its far side reported no host or directory"
            f" (the tab's host {tab.host!r} is the local one); saved as the login"
        )
        return Plan("ssh", login=login, note=note)
    if not tab.path.startswith("/"):
        msg = f"tab {index}: iTerm2 reports directory {tab.path!r} on {tab.host!r}"
        raise ArrangementError(msg)
    # The host is asked one directory a line (dirs_argv), and the far side
    # takes none with a newline either (__ssh_arrangement_decode.fish).
    if "\n" in tab.path:
        msg = f"tab {index}: directory {tab.path!r} on {tab.host!r} holds a newline"
        raise ArrangementError(msg)
    return Plan("ssh", login=login, path=tab.path)


def parse_sessions(text: str) -> dict[str, list[tuple[str, str]]]:
    r"""Return {shown name: [(socket, session)]} from list_sessions_argv's output.

    "claude:ai-agent:vm/ai-agent\ndefault:main:main\n"
        -> {"vm/ai-agent": [("claude", "ai-agent")], "main": [("default", "main")]}
    Fields split at ":", which neither a session name (tmux allows none) nor
    a hostname holds; a space would split "my notes", whose tab then read
    as on no socket rather than as a name to rename (attach_line).
    Lines of any other shape ("no server running on ...") are what a socket
    with no server prints; they are kept only for the error in lines().
    """
    found: dict[str, list[tuple[str, str]]] = {}
    for line in text.splitlines():
        fields = line.split(":")
        if len(fields) == SESSION_FIELDS and fields[0] in SOCKETS and all(fields):
            socket, session, shown = fields
            found.setdefault(shown, []).append((socket, session))
    return found


def ssh_argv(login: str, remote: str, *, unattended: bool) -> list[str]:
    """Return the argv running `remote` over `login`, UNATTENDED_SSH first if so.

    ("ssh -p 2222 vm", "ls", unattended=True)
        -> ["ssh", "-o", "BatchMode=yes", ..., "-p", "2222", "vm", "ls"]
    First, since ssh keeps the first value it reads for an option.
    """
    first, *rest = login.split()
    return [first, *(UNATTENDED_SSH if unattended else ()), *rest, remote]


def list_sessions_argv(login: str, *, unattended: bool) -> list[str]:
    """Return the argv that lists every socket's sessions on the host of `login`.

    A line per session: its socket, its name, and the name its title shows
    (TITLED), ":"-separated (parse_sessions), tmux formatting both on the far
    side so the host is that one's.
    The remote command is one word for ssh; its single quotes read the same
    in a remote sh and a remote fish.
    """
    remote = "; ".join(
        f"{tmux(socket)} ls -F '{socket}:#{{session_name}}:{TITLED[socket]}'"
        for socket in SOCKETS
    )
    return ssh_argv(login, remote, unattended=unattended)


def dirs_argv(login: str, *, unattended: bool) -> list[str]:
    """Return the argv that tells which directories on stdin are on `login`'s host.

    One directory a line in, "y" or "n" a line out, in order. The remote
    command is one word for ssh, run by sh whatever the login shell: its
    single quotes read the same in a remote sh and a remote fish.
    """
    script = (
        'while IFS= read -r d; do if test -d "$d"; then echo y; else echo n; fi; done'
    )
    return ssh_argv(login, f"sh -c '{script}'", unattended=unattended)


def parse_dirs(text: str, paths: list[str]) -> dict[str, bool]:
    r"""Return {path: is a directory} from dirs_argv's output for `paths`.

    ("y\nn\n", ["/a", "/b"]) -> {"/a": True, "/b": False}. Anything but one
    y or n per path (a login banner, an error) is an error, quoting it.
    """
    answers = text.splitlines()
    if len(answers) != len(paths) or not set(answers) <= {"y", "n"}:
        msg = f"want y or n for each of {len(paths)} directories, got:\n{text}"
        raise ArrangementError(msg)
    return {p: a == "y" for p, a in zip(paths, answers, strict=True)}


Lookup = Callable[[str], tuple[dict[str, list[tuple[str, str]]], str]]
DirCheck = Callable[[str, str], bool]  # (login, path) -> a directory there


def lines(plans: list[Plan], lookup: Lookup, has_dir: DirCheck) -> list[str]:
    """Return the saved lines.

    lookup(login) gives a host's tmux sessions and raw output; has_dir(login,
    path) whether the directory a tab reported is one on its login's host.
    """
    out = []
    for i, p in enumerate(plans, 1):
        if p.kind == "local":
            out.append(p.line)
            continue
        if p.kind == "ssh":
            if p.path and not has_dir(p.login, p.path):
                msg = (
                    f"tab {i}: its far side reports directory {p.path!r}, which is"
                    f" none on `{p.login}`: the tab ssh'd on from there, or the"
                    " directory is gone; cd elsewhere or close the tab"
                )
                raise ArrangementError(msg)
            out.append(dir_line(p.login, p.path) if p.path else p.login)
            continue
        found, raw = lookup(p.login)
        held = found.get(p.session, [])
        if not held:
            msg = (
                f"tab {i}: tmux session {p.session!r} is on no socket"
                f" ({', '.join(SOCKETS)}) of `{p.login}`; its tmux ls said:\n{raw}"
            )
            raise ArrangementError(msg)
        if len(held) > 1:
            msg = (
                f"tab {i}: tmux session {p.session!r} is on sockets"
                f" {' and '.join(s for s, _ in held)} of `{p.login}`; rename one"
            )
            raise ArrangementError(msg)
        out.append(attach_line(p.login, *held[0]))
    return out


# --- the script ----------------------------------------------------------------


def log(msg: str) -> None:
    """Print a UTC-stamped line and append it to the run's event log."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    print(line, flush=True)  # noqa: T201
    with LOG[0].open("a") as f:
        f.write(line + "\n")


async def read_windows(
    app: iterm2.App,
    prefix: str | None,
) -> list[tuple[str, list[Tab]]]:
    r"""Return every window, the key one first, or the one titled `prefix`...

    as (title template, tabs). The template is the raw titleOverrideFormat
    ("ai-agent \(currentTab.currentSession.name)"), not the title it
    renders; jobName and commandLine are the local foreground job, ssh for
    an ssh tab whatever runs on the far side.
    """
    windows = list(app.windows)
    key = app.current_window
    if key in windows:
        windows.remove(key)
        windows.insert(0, key)
    if prefix is not None:
        titles = [await w.async_get_variable("titleOverride") for w in windows]
        windows = [
            w for w, t in zip(windows, titles, strict=True) if t.startswith(prefix)
        ]
        if len(windows) != 1:
            msg = (
                f"{len(windows)} windows have a title starting with {prefix!r};"
                f" titles: {titles}"
            )
            raise ArrangementError(msg)
    if not windows:
        msg = "iTerm2 has no window"
        raise ArrangementError(msg)

    out = []
    for w in windows:
        template = await w.async_get_variable("titleOverrideFormat") or ""
        tabs = []
        for t in w.tabs:
            # all_sessions, not sessions: the latter leaves out the panes
            # behind a maximized one, and such a tab would pass as one pane.
            panes = t.all_sessions
            s = panes[0]
            facts = [await s.async_get_variable(v) for v in TAB_VARIABLES]
            # Every one is set for a live session: None means iTerm2 renamed
            # or dropped the variable.
            if not all(isinstance(f, str) for f in facts):
                msg = (
                    f"iTerm2 reported {facts} for {', '.join(TAB_VARIABLES)}"
                    f" of {s.session_id}"
                )
                raise ArrangementError(msg)
            tabs.append(Tab(len(panes), *facts))
        out.append((template, tabs))
    return out


async def local_host(app: iterm2.App) -> str:
    """Return iTerm2's name for this Mac: the host of the session the save runs in.

    That session runs this script, so it is local by construction
    (module docstring: the name is read, not guessed).
    """
    if "TMUX" in os.environ:
        msg = (
            "run from inside tmux: a tmux pane's ITERM_SESSION_ID is that of the"
            " tab that started its tmux session, not this one; run the script"
            " from a plain iTerm2 tab, whose host tells a remote directory from"
            " a local one"
        )
        raise ArrangementError(msg)
    if "ITERM_SESSION_ID" not in os.environ:
        msg = (
            "ITERM_SESSION_ID is unset: run the script from an iTerm2 tab, whose"
            " host tells a remote directory from a local one"
        )
        raise ArrangementError(msg)
    sid = os.environ["ITERM_SESSION_ID"]
    session = app.get_session_by_id(sid.partition(":")[2])
    if session is None:
        msg = f"ITERM_SESSION_ID {sid!r} names no session of this iTerm2"
        raise ArrangementError(msg)
    host = await session.async_get_variable("hostname")
    if not isinstance(host, str) or not host:
        msg = f"iTerm2 reported hostname {host!r} for this session ({sid})"
        raise ArrangementError(msg)
    return host


async def local_hosts(
    app: iterm2.App,
    windows: list[tuple[str, list[Tab]]],
) -> frozenset[str]:
    """Return iTerm2's names for this Mac, for a snapshot, which runs in no tab.

    Read, not guessed, as local_host does, from the tabs whose foreground
    job is not ssh, which run here, plus iTerm2's own localhostName. iTerm2
    names one Mac both ways at once:

        fish tabs        hostname "<LocalHostName>.local" (most)
                                  "<hostname>"            (some)
        localhostName    "<hostname>"

    A tab on another host behind a job other than ssh (mosh, docker exec)
    would pass its host off as local: an ssh tab to that host is then saved
    as its login alone, with a note in the log.
    """
    names = {t.host for _, tabs in windows for t in tabs if t.job != "ssh"}
    return frozenset({*names, await own_host(app)})


async def own_host(app: iterm2.App) -> str:
    """Return iTerm2's own name for this Mac, its localhostName."""
    own = await app.async_get_variable("localhostName")
    if not isinstance(own, str) or not own:
        msg = f"iTerm2 reported localhostName {own!r}"
        raise ArrangementError(msg)
    return own


async def fresh_host(
    label: str,
    session: iterm2.Session,
    timeout: float = FRESH_HOST_TIMEOUT,
    poll: float = 0.05,
) -> str:
    """Return the host a tab just opened reports: a name for this Mac, read.

    Nothing is typed into it yet, so it runs the default profile's local
    shell, beside an ssh tab too; iTerm2 sets its hostname within ~0.1 s.
    """
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while True:
        host = await session.async_get_variable("hostname")
        if isinstance(host, str) and host:
            return host
        if loop.time() >= deadline:
            msg = (
                f"{label}: iTerm2 reported hostname {host!r} for the new tab"
                f" after {timeout:g} s"
            )
            raise ArrangementError(msg)
        await asyncio.sleep(poll)


def snapshot_name(now: datetime) -> str:
    """Return the name of a snapshot taken at `now`: "auto-20261019_143000"."""
    return f"{SNAPSHOT_PREFIX}{now:%Y%m%d_%H%M%S}"


def stale_snapshots(names: list[str]) -> list[str]:
    """Return the snapshots among `names` past the newest SNAPSHOT_KEEP of them.

    Kept by count, not age: a day without snapshots (iTerm2 quit over a
    weekend) must not cost the last ones from before it, the very ones a
    restore wants. Ordered by the time in the name, not the file's mtime,
    which a hand edit moves. A name of no other shape under the prefix is a
    file this script did not write: an error, not something to delete or skip.
    """
    taken = []
    for name in names:
        if not name.startswith(SNAPSHOT_PREFIX):
            continue
        stamp = name.removeprefix(SNAPSHOT_PREFIX)
        try:
            when = datetime.strptime(stamp, "%Y%m%d_%H%M%S").replace(tzinfo=UTC)
        except ValueError as e:
            msg = (
                f"arrangement {name!r} has the snapshot prefix but no"
                f" YYYYMMDD_HHMMSS time after it; rename or remove {DIR / name}.txt"
            )
            raise ArrangementError(msg) from e
        taken.append((when, name))
    return [name for _, name in sorted(taken, reverse=True)[SNAPSHOT_KEEP:]]


async def snapshot(app: iterm2.App) -> None:
    """Save every window as a new snapshot, then drop all but the newest SNAPSHOT_KEEP.

    Old ones go only after a save went through: while saves fail, the last
    good snapshots are kept, however old.
    """
    await save(app, snapshot_name(datetime.now(UTC)), None, snapshot=True)
    names = [p.stem for p in DIR.glob(f"{SNAPSHOT_PREFIX}*.txt")]
    stale = stale_snapshots(names)
    for name in stale:
        (DIR / f"{name}.txt").unlink()
    log(f"removed {len(stale)} snapshots past the newest {SNAPSHOT_KEEP}")


def remote_lookup(*, unattended: bool) -> Lookup:
    """Return a lookup asking each host once which tmux sockets hold which sessions."""
    cache: dict[str, tuple[dict[str, list[tuple[str, str]]], str]] = {}

    def lookup(login: str) -> tuple[dict[str, list[tuple[str, str]]], str]:
        if login not in cache:
            log(f"asking `{login}` which tmux sockets hold which sessions")
            # tmux ls exits 1 for a socket with no server, an empty socket,
            # so only ssh's own failure (255) is one.
            done = subprocess.run(  # noqa: S603 - argv from a plain-word login
                list_sessions_argv(login, unattended=unattended),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            if done.returncode == 255:  # noqa: PLR2004 - ssh's own error exit
                msg = f"`{login}` failed to connect:\n{done.stdout}"
                raise ArrangementError(msg)
            cache[login] = (parse_sessions(done.stdout), done.stdout)
        return cache[login]

    return lookup


def remote_dirs(plans: list[Plan], *, unattended: bool) -> DirCheck:
    """Return a check asking each host once whether its tabs' directories are there."""
    wanted: dict[str, list[str]] = {}
    for p in plans:
        if p.kind == "ssh" and p.path and p.path not in wanted.setdefault(p.login, []):
            wanted[p.login].append(p.path)

    found: dict[tuple[str, str], bool] = {}
    for login, paths in wanted.items():
        log(f"asking `{login}` whether its tabs' {len(paths)} directories are there")
        done = subprocess.run(  # noqa: S603 - argv from a plain-word login
            dirs_argv(login, unattended=unattended),
            input="".join(f"{path}\n" for path in paths),
            capture_output=True,
            text=True,
            check=False,
        )
        if done.returncode != 0:
            msg = (
                f"`{login}` failed to check directories (exit {done.returncode}):"
                f"\n{done.stdout}{done.stderr}"
            )
            raise ArrangementError(msg)
        try:
            answers = parse_dirs(done.stdout, paths)
        except ArrangementError as e:
            msg = f"`{login}`: {e}"
            raise ArrangementError(msg) from e
        found.update({(login, path): ok for path, ok in answers.items()})
    return lambda login, path: found[login, path]


@contextmanager
def naming(wi: int, template: str) -> Generator[None, None, None]:
    """Prefix an ArrangementError raised inside with window `wi` and its template."""
    try:
        yield
    except ArrangementError as e:
        msg = f"window {wi} (title template {template!r}): {e}"
        raise ArrangementError(msg) from e


async def save(
    app: iterm2.App,
    name: str,
    prefix: str | None,
    *,
    snapshot: bool = False,
) -> None:
    """Save every window (or the one titled `prefix`...) as arrangement `name`."""
    windows = await read_windows(app, prefix)
    # A save run by hand reads the local host off its own tab; a snapshot
    # has no tab of its own and reads it off the windows (local_hosts).
    if snapshot:
        local = await local_hosts(app, windows)
    else:
        local = frozenset({await local_host(app)})
    which = f"the window titled {prefix!r}..." if prefix else "every window"
    log(f"save {name}: {len(windows)} windows ({which}); local hosts {sorted(local)}")

    # Any tab that cannot be saved fails the whole save, naming its window:
    # a file missing a window would restore less than was there, silently.
    # Every tab is planned before any host is asked, so each host is asked
    # about all its tabs' directories in one ssh.
    plans_of = []
    for wi, (template, tabs) in enumerate(windows, 1):
        with naming(wi, template):
            plans_of.append([plan(t, i, local) for i, t in enumerate(tabs, 1)])
    all_plans = [p for plans in plans_of for p in plans]
    has_dir = remote_dirs(all_plans, unattended=snapshot)
    lookup = remote_lookup(unattended=snapshot)
    saved = []
    for wi, ((template, _), plans) in enumerate(zip(windows, plans_of, strict=True), 1):
        with naming(wi, template):
            got = lines(plans, lookup, has_dir)
        saved.append(Saved(template, got))
        log(f"window {wi}: {len(got)} tabs, title template {template!r}")
        for i, line in enumerate(got, 1):
            log(f"  tab {i}: {line}")
        for p in plans:
            if p.note:
                log(f"  note: {p.note}")

    # Written beside its final name and renamed into place, so a failed save
    # never leaves half a file where a good one was.
    DIR.mkdir(parents=True, exist_ok=True)
    file = DIR / f"{name}.txt"
    tmp = file.with_suffix(".txt.tmp")
    tmp.write_text(render(name, f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ}", saved))
    tmp.replace(file)
    log(f"saved {file}")


def load(name: str) -> list[Saved]:
    """Return the windows of arrangement `name`; a missing or bad file is an error."""
    file = DIR / f"{name}.txt"
    if not file.exists():
        names = sorted(p.stem for p in DIR.glob("*.txt")) if DIR.exists() else []
        msg = (
            f"no arrangement {name!r}: {file} does not exist;"
            f" saved ones: {names or '(none)'}"
        )
        raise ArrangementError(msg)
    try:
        return parse_file(file.read_text())
    except ArrangementError as e:
        msg = f"{file}: {e}"
        raise ArrangementError(msg) from e


async def restore(
    connection: iterm2.Connection,
    app: iterm2.App,
    name: str,
    windows: list[Saved],
    *,
    alone: bool = False,
) -> None:
    """Open a new window per saved one, the first saved one in front.

    `alone` (relaunch): then close every other window, what iTerm2 opened at
    its launch. Last, so one it opened late is gone too; and on a failure as
    well, so a tab that never lands leaves no startup window beside the rest.
    """
    opened: list[iterm2.Window] = []
    try:
        await open_windows(connection, app, windows, opened)
    finally:
        if alone:
            await close_windows(app, keep={w.window_id for w in opened})
    log(f"restored {name}: {len(windows)} windows")


async def open_windows(
    connection: iterm2.Connection,
    app: iterm2.App,
    windows: list[Saved],
    opened: list[iterm2.Window],
) -> None:
    """Open `windows`, appending each to `opened`, and wait until all land."""
    # A directory tab has landed only off the local host (dir_landing). Its
    # names are read off the directory tabs opened here, each before
    # anything is typed into it (fresh_host), with iTerm2's own: no tab of
    # the caller's needed.
    local = {await own_host(app)}

    # Last window first, the first one activated at the end: it was the
    # key window when saved. Each title is read back, as a window left with
    # the wrong name is a failure, not a skip.
    typed: list[tuple[str, str, iterm2.Session]] = []
    for wi in reversed(range(len(windows))):
        w = windows[wi]
        window = await iterm2.Window.async_create(connection)
        if window is None or window.current_tab is None:
            msg = f"iTerm2 made no window for saved window {wi + 1}"
            raise ArrangementError(msg)
        # Counted as opened before any tab of it can fail: a relaunch's
        # cleanup then keeps it, ssh sessions that connected and all, and
        # the error names a window that is still there.
        opened.append(window)
        for i, line in enumerate(w.lines):
            tab = window.current_tab if i == 0 else await window.async_create_tab()
            if tab is None or tab.current_session is None:
                msg = f"iTerm2 made no tab {i + 1} in window {wi + 1}"
                raise ArrangementError(msg)
            label = f"window {wi + 1} tab {i + 1}"
            if dir_request(line) is not None:
                local.add(await fresh_host(label, tab.current_session))
            await tab.current_session.async_send_text(line + "\n")
            log(f"{label}: {line}")
            typed.append((label, line, tab.current_session))
        if w.template:
            await window.async_set_title(w.template)
            got = await window.async_get_variable("titleOverrideFormat")
            if got != w.template:
                msg = (
                    f"window {wi + 1}: title template reads back {got!r},"
                    f" want {w.template!r}"
                )
                raise ArrangementError(msg)
        log(f"window {wi + 1} restored ({window.window_id}): {w.template!r}")
    await opened[-1].async_activate()

    # Landings are made once every tab has added its name for this Mac.
    hosts = frozenset(local)
    log(f"local hosts {sorted(hosts)}")
    landing = [
        lands
        for label, line, s in typed
        if (lands := landing_of(label, line, s, hosts))
    ]
    await wait_landed(landing)


async def close_windows(app: iterm2.App, keep: set[str]) -> None:
    """Close every window of iTerm2's but those with ids in `keep`, unasked."""
    await app.async_refresh()
    for w in list(app.windows):
        if w.window_id not in keep:
            log(f"closing window {w.window_id} ({len(w.tabs)} tabs)")
            await w.async_close(force=True)


Reach = Callable[[iterm2.Session], Awaitable[tuple[bool, str]]]


@dataclass
class Landing:
    """A restored tab, and how to tell it reached what was saved.

    reach(session) -> (landed, what the tab shows now, said for the error).
    """

    label: str  # "window 1 tab 2"
    want: str  # what it must come to show, as the error says it
    session: iterm2.Session
    reach: Reach


def tmux_landing(
    label: str,
    socket: str,
    name: str,
    session: iterm2.Session,
) -> Landing:
    """Return the landing of a tab that attaches tmux session `name` on `socket`.

    Landed once its title shows the session as TITLED does (~/.tmux.conf's
    set-titles-string for an iTerm2 client): "[main] " for default:main,
    "[vm/api/docs]" for claude:api/docs. The saved line does not name the
    far side's host, so on the claude socket any "<host>/" prefix will do
    (a hostname holds no "/", so the first one ends it).
    """
    shows = {"claude": f"<host>/{name}", "default": name}[socket]

    async def reach(s: iterm2.Session) -> tuple[bool, str]:
        title = await s.async_get_variable("name")
        shown = tmux_session(title) if isinstance(title, str) else None
        if socket == "claude":
            host, sep, rest = (shown or "").partition("/")
            landed = bool(host) and bool(sep) and rest == name
        else:
            landed = shown == name
        return landed, f"title reads {title!r}"

    return Landing(label, f"[{shows}]", session, reach)


def dir_landing(
    label: str,
    path: str,
    local: frozenset[str],
    session: iterm2.Session,
) -> Landing:
    """Return the landing of a tab that logs in to land in `path`.

    Landed once it is in `path` on a host none of `local` (this Mac's names),
    both as the far side's prompt reports them (OSC 7, iterm2_report_host).
    The host too: the tab starts local, maybe in the very path (Mac-to-Mac
    ssh, /Users/me), which would count as landed before ssh had connected.
    """

    async def reach(s: iterm2.Session) -> tuple[bool, str]:
        got = await s.async_get_variable("path")
        host = await s.async_get_variable("hostname")
        return got == path and host not in local, f"path reads {got!r} on host {host!r}"

    off = ", ".join(repr(h) for h in sorted(local))
    return Landing(label, f"directory {path!r} off host {off}", session, reach)


def landing_of(
    label: str,
    line: str,
    session: iterm2.Session,
    local: frozenset[str],
) -> Landing | None:
    """Return what the tab typed `line` must come to show; None for a plain line.

    `local` are this Mac's names, which a directory tab must have left.
    """
    if request := attach_request(line):
        return tmux_landing(label, *request, session)
    if (where := dir_request(line)) is not None:
        return dir_landing(label, where, local, session)
    return None


async def wait_landed(
    tabs: list[Landing],
    timeout: float = LANDING_TIMEOUT,
    poll: float = 0.5,
) -> None:
    """Wait until each restored tab shows its tmux session or its directory.

    The title shows the session once the far side's login fish has exec'd
    tmux; the path shows the directory once it has cd'd there and drawn a
    prompt. Neither at `timeout`: the request was dropped on the way or not
    acted on, and the restore fails naming the tab, rather than leaving a
    plain shell in ~ where a session or a directory was saved.
    """
    waiting = list(tabs)
    log(f"waiting up to {timeout:g} s for {len(waiting)} tabs to land")
    deadline = asyncio.get_running_loop().time() + timeout
    seen: dict[str, str] = {}
    while waiting:
        for tab in list(waiting):
            landed, seen[tab.label] = await tab.reach(tab.session)
            if landed:
                log(f"{tab.label}: landed, {seen[tab.label]}")
                waiting.remove(tab)
        if waiting and asyncio.get_running_loop().time() >= deadline:
            msg = (
                f"{len(waiting)} tabs did not land in {timeout:g} s:\n"
                + "\n".join(
                    f"  {tab.label}: want {tab.want}, {seen[tab.label]}"
                    for tab in waiting
                )
                + "\nOn the far side, the tmux_attach_requested and"
                " login_dir_requested event logs"
                " (~/.dotfiles/.logs/*_<name>/events.log) show each request"
                " received: none means LC_TMUX_ATTACH or LC_LOGIN_DIR never"
                " arrived (sshd AcceptEnv, or the host runs no fish with those"
                " functions: dotup it); a line says what was refused."
            )
            raise ArrangementError(msg)
        if waiting:
            await asyncio.sleep(poll)


# --- relaunch: iTerm2 quit and launched around a restore -----------------------


def iterm2_ancestor(pid: int, parent: Callable[[int], tuple[int, str]]) -> str | None:
    """Return the iTerm2 process `pid` runs under, as "<pid> <path>"; else None.

    parent(pid) -> (its parent's pid, its executable path), as ps says. A
    tab's shell runs under iTermServer, under iTerm2:
        fish -> iTermServer-3.7.6 -> iTerm2       -> "95610 .../iTermServer-3.7.6"
        fish -> Terminal                          -> None
    A tmux server forks off to launchd, so its panes run under no iTerm2,
    whichever terminal started it.
    """
    while pid > 1:
        ppid, path = parent(pid)
        exe = Path(path).name
        if exe == "iTerm2" or exe.startswith("iTermServer"):
            return f"{pid} {path}"
        pid = ppid
    return None


def ps_parent(pid: int) -> tuple[int, str]:
    """Return (parent pid, executable path) of process `pid`, from ps."""
    done = subprocess.run(  # noqa: S603 - fixed argv
        ["ps", "-o", "ppid=,comm=", "-p", str(pid)],  # noqa: S607 - ps from PATH
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        msg = f"ps -p {pid} failed (exit {done.returncode}): {done.stderr.strip()}"
        raise ArrangementError(msg)
    ppid, path = done.stdout.strip().split(None, 1)
    return int(ppid), path


def osascript(script: str) -> str:
    """Run AppleScript `script`; return its output, failing on any error."""
    done = subprocess.run(  # noqa: S603 - fixed argv
        ["osascript", "-e", script],  # noqa: S607 - macOS's own osascript
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        msg = (
            f"osascript `{script}` failed (exit {done.returncode}):"
            f" {done.stderr.strip()}"
        )
        raise ArrangementError(msg)
    return done.stdout.strip()


def iterm2_running() -> bool:
    """Tell whether iTerm2 runs; asking so sends it no Apple event."""
    return osascript(f'application id "{ITERM2_BUNDLE}" is running') == "true"


def quit_iterm2() -> None:
    """Quit iTerm2 and wait until it has exited.

    With every window closed it asks nothing; were it to ask "Quit iTerm2?"
    anyway, the osascript waits on the answer (up to AppleScript's 2 min).
    An iTerm2 set to quit when its last window closes is gone already.
    """
    if not iterm2_running():
        log("iTerm2 exited with its last window")
        return
    log("quitting iTerm2 (answer its prompt, if it shows one)")
    osascript(f'tell application id "{ITERM2_BUNDLE}" to quit')
    start = time.monotonic()
    note = start + PROGRESS_EVERY
    while iterm2_running():
        now = time.monotonic()
        if now >= start + RELAUNCH_TIMEOUT:
            msg = f"iTerm2 still runs {RELAUNCH_TIMEOUT} s after it was told to quit"
            raise ArrangementError(msg)
        if now >= note:
            log(f"iTerm2 still runs {now - start:.0f} s after it was told to quit")
            note += PROGRESS_EVERY
        time.sleep(0.2)
    log("iTerm2 has exited")


def connected(
    act: Callable[[iterm2.Connection, iterm2.App], Awaitable[None]],
    *,
    wait: float = 0,
) -> None:
    """Run act(connection, app) on a connection to iTerm2.

    `wait`: s to keep retrying the connection, for an iTerm2 just launched
    whose API may not answer yet (relaunch); 0 tries once. Retried are no
    socket yet (OSError) and a handshake it fails while it starts: a 401 if
    it gave no cookie yet, or the InvalidMessage the package's own
    async_connect retries. A connection refused at the end is an error
    naming why, in the log, rather than the package's message on stderr
    alone (run_until_complete's).

    Once per process: the package keeps its App, message helpers and
    notification subscriptions process-wide, bound to the first connection
    (relaunch).
    """

    async def run() -> None:
        loop = asyncio.get_running_loop()
        start = loop.time()
        note = start + PROGRESS_EVERY
        while True:
            try:
                connection = await iterm2.Connection.async_create()
                break
            except (OSError, websockets.exceptions.InvalidHandshake) as e:
                now = loop.time()
                if now < start + wait:
                    if now >= note:
                        log(f"no API connection after {now - start:.0f} s: {e!r}")
                        note += PROGRESS_EVERY
                    await asyncio.sleep(0.5)
                    continue
                if not iterm2_running():
                    msg = (
                        "iTerm2 is not running; `iterm2_ssh_arrangement.sh"
                        " relaunch <name>` launches it and restores"
                    )
                else:
                    msg = (
                        f"iTerm2 runs but refused an API connection ({e})"
                        + (f" for {wait:g} s after its launch" if wait else "")
                        + ": is its Python API on (Settings > General > Magic)?"
                    )
                raise ArrangementError(msg) from e
        await act(connection, await app_of(connection))

    asyncio.run(run())


async def app_of(connection: iterm2.Connection) -> iterm2.App:
    """Return iTerm2's app object over `connection`."""
    app = await iterm2.async_get_app(connection)
    if app is None:
        msg = "iTerm2's Python API returned no app"
        raise ArrangementError(msg)
    return app


def relaunch(name: str) -> None:
    """Quit iTerm2, its windows closed first, launch it, and restore `name` alone."""
    # Both checks come before anything closes: a run that stops later
    # leaves no windows, or no iTerm2, and nothing restored.
    windows = load(name)
    if under := iterm2_ancestor(os.getpid(), ps_parent):
        msg = (
            f"runs under iTerm2 ({under}), so quitting iTerm2 would end it before"
            " the restore; run it from another terminal app (Terminal, Ghostty),"
            " or `restore` to add the windows to those open"
        )
        raise ArrangementError(msg)

    # Every window closed first: iTerm2 then asks no "Quit iTerm2?" and
    # keeps no windows to restore at its next launch (NSQuitAlwaysKeepsWindows).
    # In a child process, as the package allows one connection a process:
    # a second one here, to the new iTerm2, ran the first one's helpers on
    # every message, which failed on its closed socket, and the new App
    # missed the tabs it made (seen 2026-10-26: "iTerm2 made no tab 2").
    # Spawned, not forked, so it imports the package afresh; and no command
    # of the script's, which a stray `_close-all` typed in a tab would run.
    if iterm2_running():
        in_child(close_all, LOG[0], timeout=CLOSE_TIMEOUT, what="closing every window")
        quit_iterm2()
    log("launching iTerm2")
    done = subprocess.run(  # noqa: S603 - fixed argv
        ["open", "-b", ITERM2_BUNDLE],  # noqa: S607 - macOS's own open
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        msg = (
            f"open -b {ITERM2_BUNDLE} failed (exit {done.returncode}):"
            f" {done.stderr.strip()}"
        )
        raise ArrangementError(msg)
    connected(
        lambda c, app: restore(c, app, name, windows, alone=True),
        wait=RELAUNCH_TIMEOUT,
    )


def close_all(log_file: Path) -> None:
    """Close every window of iTerm2's, unasked: relaunch's child (in_child)."""
    LOG.append(log_file)
    try:
        connected(lambda _c, app: close_windows(app, keep=set()))
    except ArrangementError as e:
        log(f"ERROR: {e}")
        sys.exit(1)


def in_child(
    target: Callable[..., None],
    *args: object,
    timeout: float,
    what: str,
) -> None:
    """Run target(*args) in a spawned process; its failure or overrun is an error.

    A child left past `timeout` is killed: one whose iTerm2 quit under it
    (QuitWhenAllWindowsClosed) can wait forever on an answer to a close.
    """
    child = multiprocessing.get_context("spawn").Process(target=target, args=args)
    child.start()
    child.join(timeout)
    if child.exitcode is None:
        child.kill()
        child.join()
        msg = f"{what} took over {timeout:g} s; killed it"
        raise ArrangementError(msg)
    if child.exitcode != 0:
        msg = f"{what} failed (exit {child.exitcode}); see above"
        raise ArrangementError(msg)


def main() -> None:
    """Parse argv (<event log> <command> [<name> [<prefix>]]), connect, and act."""
    LOG.append(Path(sys.argv[1]))
    args = sys.argv[2:]
    command, name, prefix = [*args, None, None, None][:3]
    name = name or "all"
    if (
        command not in ("save", "restore", "relaunch", "snapshot")
        or len(args) > MAX_ARGS
        or (command in ("restore", "relaunch") and prefix)
        or (command == "snapshot" and len(args) > 1)
    ):
        log(f"ERROR: {USAGE}")
        sys.exit(1)
    if not re.fullmatch(r"[\w.-]+", name, re.ASCII):
        log(f"ERROR: name {name!r}: use letters, digits, '.', '_', '-'")
        sys.exit(1)
    # Snapshots are pruned by this prefix: a save under it would be pruned,
    # or, not named by a time, stop every snapshot's pruning.
    if command == "save" and name.startswith(SNAPSHOT_PREFIX):
        log(f"ERROR: name {name!r}: {SNAPSHOT_PREFIX!r} is for snapshots alone")
        sys.exit(1)

    # An ArrangementError is a finding about the windows, the file or
    # iTerm2, said in one line; anything else is a bug and keeps its
    # traceback.
    try:
        if command == "save":
            connected(lambda _c, app: save(app, name, prefix))
        elif command == "snapshot":
            connected(lambda _c, app: snapshot(app))
        elif command == "restore":
            windows = load(name)
            connected(lambda c, app: restore(c, app, name, windows))
        else:
            relaunch(name)
    except ArrangementError as e:
        log(f"ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

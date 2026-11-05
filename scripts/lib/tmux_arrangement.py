r"""What the terminals' tmux arrangements share, whichever terminal holds the tabs.

    iterm2_ssh_arrangement.py    ghostty_tmux_arrangement.py
            |                              |
            +-------------+----------------+
                          v
    this file: which tmux sessions a host holds (remote_lookup), the line
    that attaches one over ssh (attach_for, attach_line), and how snapshots
    are named and pruned

Only the standard library and ssh_command.py, so the Ghostty script and the
tests run on plain python3; iTerm2's API stays in its own script. The attach
line, and why it goes through the login shell, is explained in
iterm2_ssh_arrangement.py's docstring.
"""

# A script beside its shell wrapper, no license header, as in scripts/tests.
# ruff: noqa: INP001, CPY001

import os
import re
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import quote, unquote

# The parser lives beside its first user, Cmd-T's iterm2_api.py.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "home/.hammerspoon"))
import ssh_command

# A socket a saved line may name: any tmux socket, found by looking
# (local_sockets, LIST_SESSIONS), as long as it needs no quoting and reads as
# no option. tmux_attach_requested.fish holds the same pattern, as what it
# gets arrives over ssh.
SOCKET_NAME = re.compile(r"[A-Za-z0-9_.][A-Za-z0-9_.-]*")
# What a host runs to list its sessions: a line per session, on every socket
# in tmux's directory. In sh whatever the login shell is, and with its outer
# single quotes the same words to a remote sh and a remote fish. A socket file
# outliving its server prints "no server running ..." and lists nothing.
#   /tmp/tmux-1000/{default,work} -> tmux-session:default:main
#                                    tmux-session:work:api/docs
LIST_SESSIONS = (
    """sh -c 'for p in "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"/*; do"""
    """ [ -S "$p" ] && s=${p##*/} &&"""
    """ tmux -L "$s" ls -F "tmux-session:$s:#{session_name}"; done'"""
)
# The mark sets a session apart from what ssh or a login shell prints beside
# it. Fields split at ":", which a session name (tmux allows none) lacks.
SESSION_LINE = re.compile(r"tmux-session:([^:]+):(.+)")
LIST_CLIENTS_FIELDS = 3  # a local_clients line: tty, session, directory
# tmux list-clients on a socket with no server: nothing attached, no error.
NO_SERVER = re.compile(r"no server running|error connecting to")
LOCAL_LINE = re.compile(
    r"tmux(?: -L (\S+))? new-session -A -s '((?:[^'\\]|\\.)*)' -c '((?:[^'\\]|\\.)*)'",
)
SNAPSHOT_PREFIX = "auto-"  # snapshot "auto-20261019_143000", a UTC time
# Two weeks of them (14 x 144) at Hammerspoon's one per 10 minutes
# (snapshots.lua): long enough that a run of snapshots taken after a drop,
# every ssh tab a dead local shell, does not push out the last good one
# before it is missed (2026-10-31: a day's worth did). About 3 KB each, so
# some 6 MB in all.
SNAPSHOT_KEEP = 14 * 144
# What a snapshot's ssh may not do: ask for anything (no tty to answer on)
# or wait out a host that is down for the TCP timeout.
UNATTENDED_SSH = ("-o", "BatchMode=yes", "-o", "ConnectTimeout=10")
LOG: list[Path] = []  # the run's event log, set by main()

# (login) -> ({session: [sockets holding one of that name]}, what the host printed)
Lookup = Callable[[str], tuple[dict[str, list[str]], str]]


class ArrangementError(Exception):
    """A save or restore that would leave the wrong thing; the message says what."""


@dataclass
class Client:
    """A local tmux client: the session it shows, and that session's directory."""

    socket: str
    session: str
    path: str


def log(msg: str) -> None:
    """Print a UTC-stamped line and append it to the run's event log."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    print(line, flush=True)  # noqa: T201
    with LOG[0].open("a") as f:
        f.write(line + "\n")


def tmux_session(title: str) -> str | None:
    """Return the tmux session a tab title shows, or None.

    "[api/docs]" -> "api/docs"; "[main]" -> "main"; "fish:~" -> None.
    """
    m = re.fullmatch(r"\[(.+)\]", title)
    return m[1] if m else None


def tmux(socket: str) -> str:
    """Return the tmux command for `socket`: "tmux" or "tmux -L work"."""
    return "tmux" if socket == "default" else f"tmux -L {socket}"


def attach_line(login: str, socket: str, session: str) -> str:
    """Return the line that reattaches `session` on `socket`, via the login shell.

    ("ssh -p 2222 vm", "work", "ai-agent")
        -> "LC_TMUX_ATTACH=work:ai-agent ssh -o SendEnv=LC_TMUX_ATTACH -p 2222 vm"
    The value is "<socket>:<session>", split at the first ":" on the far
    side; tmux allows no ":" in a session name. LC_ because the stock
    AcceptEnv of sshd (LANG LC_*) passes only those.

    "/" goes as "%2F": Tailscale SSH (1.102) drops a variable whose value
    holds a "/", so "work:api/docs" never arrived, while every other
    character a plain session name may hold passes. A plain name holds no
    "%", so tmux_attach_requested.fish decodes it unambiguously:
        "api/docs" -> "LC_TMUX_ATTACH=work:api%2Fdocs ..."
    """
    if not ssh_command.plain(session):
        msg = f"tmux session {session!r} has characters needing quotes; rename it"
        raise ArrangementError(msg)
    return send_line(login, "LC_TMUX_ATTACH", f"{socket}:{session}")


def send_line(login: str, variable: str, value: str) -> str:
    """Return `login` sending `variable`=`value` to the far side's login shell.

    ("ssh -p 2222 vm", "LC_X", "a/b c")
        -> "LC_X=a%2Fb%20c ssh -o SendEnv=LC_X -p 2222 vm"
    Every byte but [A-Za-z0-9_.~:-] is %-encoded: the "/" for Tailscale SSH
    (attach_line), the rest so the value needs no quoting in fish. ":" stays,
    so a tmux line reads as before ("work:api%2Fdocs"). The far side
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
    "LC_TMUX_ATTACH=work:api%2Fdocs ssh -o SendEnv=LC_TMUX_ATTACH vm"
        -> ("work", "api/docs")
    An attach line no restore can land -- a socket that is no plain name, no
    session -- is an error (a hand edit, or a file older than this script).
    """
    value = sent_value(line, "LC_TMUX_ATTACH")
    if value is None:
        return None
    socket, _, session = value.partition(":")
    if not SOCKET_NAME.fullmatch(socket):
        msg = f"attaches on tmux socket {socket!r}, not a plain name: {line}"
        raise ArrangementError(msg)
    if not session:
        msg = f"attaches no session on socket {socket!r}: {line}"
        raise ArrangementError(msg)
    return socket, session


def fish_quote(s: str) -> str:
    r"""Quote `s` for fish: inside '...' only \ and ' are special."""
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def parse_sessions(text: str) -> dict[str, list[str]]:
    r"""Return {session: [sockets holding it]} from list_sessions_argv's output.

    "tmux-session:work:api\ntmux-session:default:main\n"
        -> {"api": ["work"], "main": ["default"]}
    A space stays in its field, so "my notes" reads as a name to rename
    (attach_line), not as on no socket.
    Lines of any other shape ("no server running on ...") are what a socket
    with no server prints; they are kept only for attach_for's error.
    """
    found: dict[str, list[str]] = {}
    for line in text.splitlines():
        if m := SESSION_LINE.fullmatch(line):
            found.setdefault(m[2], []).append(m[1])
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
    """Return the argv that lists every socket's sessions on the host of `login`."""
    return ssh_argv(login, LIST_SESSIONS, unattended=unattended)


def remote_lookup(*, unattended: bool) -> Lookup:
    """Return a lookup asking each host once which tmux sockets hold which sessions."""
    cache: dict[str, tuple[dict[str, list[str]], str]] = {}

    def lookup(login: str) -> tuple[dict[str, list[str]], str]:
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


def attach_for(tab: int, login: str, shown: str, lookup: Lookup) -> str:
    """Return the attach line of tab number `tab`, showing tmux session `shown`.

    A session on no socket of the host, or on two, is an error: the title
    cannot say which to attach.
    """
    found, raw = lookup(login)
    held = found.get(shown, [])
    if not held:
        msg = (
            f"tab {tab}: tmux session {shown!r} is on no socket"
            f" of `{login}`; its tmux ls said:\n{raw}"
        )
        raise ArrangementError(msg)
    if len(held) > 1:
        msg = (
            f"tab {tab}: tmux session {shown!r} is on sockets"
            f" {' and '.join(held)} of `{login}`; rename one"
        )
        raise ArrangementError(msg)
    return attach_line(login, held[0], shown)


def snapshot_name(now: datetime) -> str:
    """Return the name of a snapshot taken at `now`: "auto-20261019_143000"."""
    return f"{SNAPSHOT_PREFIX}{now:%Y%m%d_%H%M%S}"


def stale_snapshots(names: list[str], directory: Path) -> list[str]:
    """Return the snapshots among `names` past the newest SNAPSHOT_KEEP of them.

    Kept by count, not age: a day without snapshots (the terminal quit over a
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
                f" YYYYMMDD_HHMMSS time after it;"
                f" rename or remove {directory / name}.txt"
            )
            raise ArrangementError(msg) from e
        taken.append((when, name))
    return [name for _, name in sorted(taken, reverse=True)[SNAPSHOT_KEEP:]]


# --- local tmux, and this process ---------------------------------------------


def run(argv: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    """Run `argv`, capturing its output; a hang is an error, not a stuck snapshot."""
    try:
        return subprocess.run(  # noqa: S603 - argv of fixed tools
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        msg = f"`{' '.join(argv[:2])}` gave no answer in {timeout:.0f}s"
        raise ArrangementError(msg) from e


def fish_unquote(quoted: str) -> str:
    r"""Undo fish_quote() on what was between the quotes: "it\'s" -> "it's"."""
    return re.sub(r"\\(.)", r"\1", quoted)


def local_line(client: Client) -> str:
    r"""Return the line that attaches a local session, or creates it if it is gone.

    Client("work", "api", "/Users/me/it's")
      -> tmux -L work new-session -A -s 'api' -c '/Users/me/it\'s'
    """
    session, path = fish_quote(client.session), fish_quote(client.path)
    return f"{tmux(client.socket)} new-session -A -s {session} -c {path}"


def local_request(line: str) -> Client | None:
    """Return what local_line() asks for, or None for any other line."""
    m = LOCAL_LINE.fullmatch(line)
    if not m:
        return None
    socket = m[1] or "default"
    if not SOCKET_NAME.fullmatch(socket):
        msg = f"uses tmux socket {socket!r}, not a plain name: {line}"
        raise ArrangementError(msg)
    return Client(socket, fish_unquote(m[2]), fish_unquote(m[3]))


def parse_clients(socket: str, text: str) -> dict[str, Client]:
    """Return {tty: Client} from `tmux list-clients` in LIST_CLIENTS format.

    "/dev/ttys005:api:/Users/me" -> {"/dev/ttys005": Client(socket, "api", ...)}
    Neither a tty nor a session name holds a ":"; a directory may.
    """
    clients = {}
    for line in text.splitlines():
        fields = line.split(":", LIST_CLIENTS_FIELDS - 1)
        if len(fields) != LIST_CLIENTS_FIELDS:
            msg = f"tmux -L {socket} list-clients printed {line!r}"
            raise ArrangementError(msg)
        clients[fields[0]] = Client(socket, fields[1], fields[2])
    return clients


def socket_dir() -> Path:
    """Return the directory of this user's tmux sockets, as tmux works it out."""
    tmp = os.environ.get("TMUX_TMPDIR") or "/tmp"  # noqa: S108 - tmux's own default
    return Path(tmp) / f"tmux-{os.getuid()}"


def local_sockets(directory: Path) -> list[str]:
    """Return the tmux sockets in `directory`, none if tmux has not made it.

    A socket file can outlive its server, and is listed all the same:
    local_clients reads that as nothing attached. One whose name a saved line
    could not carry is an error, not a session to lose without a word.
    """
    if not directory.is_dir():
        return []
    sockets = sorted(p.name for p in directory.iterdir() if p.is_socket())
    for socket in sockets:
        if not SOCKET_NAME.fullmatch(socket):
            msg = f"tmux socket {socket!r} in {directory} is not a plain name"
            raise ArrangementError(msg)
    return sockets


def local_clients() -> dict[str, Client]:
    """Return {tty: Client} of every local tmux client, on every socket."""
    clients: dict[str, Client] = {}
    for socket in local_sockets(socket_dir()):
        form = "#{client_tty}:#{session_name}:#{session_path}"
        done = run([*tmux(socket).split(), "list-clients", "-F", form], 10)
        if done.returncode == 0:
            clients |= parse_clients(socket, done.stdout)
        elif not NO_SERVER.search(done.stderr):
            msg = f"tmux -L {socket} list-clients failed: {done.stderr.strip()}"
            raise ArrangementError(msg)
    return clients


def alive(client: Client) -> bool:
    """Tell whether a local session exists; a socket with no server has none."""
    target = f"={client.session}"
    argv = [*tmux(client.socket).split(), "has-session", "-t", target]
    return run(argv, 10).returncode == 0


def check_local(
    line: str,
    is_alive: Callable[[Client], bool],
    is_dir: Callable[[str], bool],
) -> None:
    """Say what a saved local line will do; fail now if it cannot be done.

    A local session a reboot ended is created empty in its saved directory,
    logged by name, its programs being gone. Its directory gone too is an
    error, for the caller to raise before any tab opens. Any other line passes.
    """
    client = local_request(line)
    if client is None or is_alive(client):
        return
    if not is_dir(client.path):
        msg = (
            f"local tmux session {client.session!r} is gone, and its directory"
            f" {client.path} is too; create the directory or remove the line"
        )
        raise ArrangementError(msg)
    log(f"recreating empty, its programs are gone: {client.session}")


def ancestor(
    pid: int,
    parent: Callable[[int], tuple[int, str]],
    is_terminal: Callable[[str], bool],
) -> str | None:
    """Return the process `pid` runs under that is_terminal(its name) picks; else None.

    Said as "<pid> <path>"; parent(pid) -> (its parent's pid, its executable
    path), as ps says. A replace closes the terminal app's windows, so it must
    not run under one. A tmux server forks off to launchd, so its panes run
    under no terminal, whichever one started it, and survive a client's close.
    """
    while pid > 1:
        ppid, path = parent(pid)
        if is_terminal(Path(path).name):
            return f"{pid} {path}"
        pid = ppid
    return None


def ps_parent(pid: int) -> tuple[int, str]:
    """Return (parent pid, executable path) of process `pid`, from ps."""
    done = run(["ps", "-o", "ppid=,comm=", "-p", str(pid)], 10)
    if done.returncode != 0:
        msg = f"ps -p {pid} failed (exit {done.returncode}): {done.stderr.strip()}"
        raise ArrangementError(msg)
    ppid, path = done.stdout.strip().split(None, 1)
    return int(ppid), path

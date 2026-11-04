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

import re
import subprocess
import sys
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import quote, unquote

# The parser lives beside its first user, Cmd-T's iterm2_api.py.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "home/.hammerspoon"))
import ssh_command

SOCKETS = ("claude", "default")  # tmux_attach_requested.fish accepts these
# What each socket's sessions show inside the brackets of the terminal title,
# as tmux formats; must match ~/.tmux.conf's set-titles-string.
TITLED = {"claude": "#{host}/#{session_name}", "default": "#{session_name}"}
SESSION_FIELDS = 3  # a list_sessions_argv line: socket, session, shown name
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

# (login) -> ({shown name: [(socket, session)]}, what the host printed)
Lookup = Callable[[str], tuple[dict[str, list[tuple[str, str]]], str]]


class ArrangementError(Exception):
    """A save or restore that would leave the wrong thing; the message says what."""


def log(msg: str) -> None:
    """Print a UTC-stamped line and append it to the run's event log."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    print(line, flush=True)  # noqa: T201
    with LOG[0].open("a") as f:
        f.write(line + "\n")


def tmux_session(title: str) -> str | None:
    """Return the name a tab title shows for its remote tmux session, or None.

    "[vm/api/docs]" -> "vm/api/docs"; "[main]" -> "main"; "fish:~" -> None.
    On the claude socket that name is "<hostname>/<session>" (TITLED); the
    lookup maps it back.
    """
    m = re.fullmatch(r"\[(.+)\]", title)
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


def fish_quote(s: str) -> str:
    r"""Quote `s` for fish: inside '...' only \ and ' are special."""
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


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
            f" ({', '.join(SOCKETS)}) of `{login}`; its tmux ls said:\n{raw}"
        )
        raise ArrangementError(msg)
    if len(held) > 1:
        msg = (
            f"tab {tab}: tmux session {shown!r} is on sockets"
            f" {' and '.join(s for s, _ in held)} of `{login}`; rename one"
        )
        raise ArrangementError(msg)
    return attach_line(login, *held[0])


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

#!/usr/bin/env python3
r"""Save a tmux server's sessions and windows, and bring them back after a reboot.

What is saved is the layout alone: each session, its windows in order, and
the directory of each window's active pane. Not the programs, not the
splits, not the text. A restored window is a fresh shell in its old
directory. The verbs are the Ghostty arrangement's
(scripts/ghostty_tmux_arrangement.sh), for one server instead of a
terminal's windows:

  snapshot          the server now, as "auto-<UTC YYYYMMDD_HHMMSS>", unless
                    it is as the newest snapshot left it; then all but the
                    newest 2016 removed (two weeks at one per 10 minutes)
  save [<name>]     the server now, as <name> (default "all")
  restore [<name>]  the saved sessions, beside what is open: one already
                    open is left as it is. <name> defaults to the newest
                    snapshot taken before this server started: after a
                    reboot, the old server's last state
  replace [<name>]  the saved sessions, in place of every session open
  list              the arrangements saved, and which one restore picks
  run               a snapshot every 10 minutes, for the server's life
                    (tmux.conf starts it)

Every verb takes the server as tmux does, after the verb: -L <name> (default
"default") or -S <socket path>, e.g. `restore -L work`.

    tmux server (the default socket, or -L <name>)
      |  at start, tmux.conf runs, for a server in tmux's own socket folder:
      |    run-shell -b "exec ~/.dotfiles/scripts/tmux_server_arrangement.py
      |                  run -S <socket>"
      v
    run: one per server (a lock), every 10 minutes:
      list-windows -a  -->  session, window, directory  -->  render()
      |                                                        |
      |   same as the newest snapshot? nothing written         v
      |   ~/.local/state/tmux_server_arrangements/<socket>/auto-<time>.txt
      v
    restore / replace (by hand): parse() --> plan --> new-session,
      new-window -c <directory> per window --> (replace) kill-session

An arrangement is plain text, to read or edit by hand: a "session" line,
then a "window" line per window, its directory the rest of the line.

    # tmux_server_arrangement.py: /tmp/tmux-1000/default, 2026-11-10T14:00:00Z
    session api
      window /home/me/src/api
      window /home/me/src/api web

What restore does with a saved session (plan_restore):

    open on the server            left as it is, and logged
    gone (a reboot ended the      created, a window per saved one, each in
      server)                     its directory
    gone, a directory gone        an error before anything opens: edit the
                                  file, or make the directory

replace opens before it closes, and refuses before it does either:

    the sessions open but not saved are the ones to close; tmux-history
      (scripts/tmux_history.py's) is never closed
    refused if this command runs in one of them, which would end it
    refused if a pane of one has anything but an idle shell in its
      foreground, by its whole command line ("bash build.sh" is busy),
      naming each; a job left in the background is not seen
    restore, then kill-session each

Never saved: session tmux-history, the history tracker's own.

One run per server, for the server's life:

    server starts         -> tmux.conf starts run; the first snapshot comes
                             10 minutes later (a server just started holds
                             nothing worth one)
    tmux.conf sourced     -> a second run finds the lock taken and exits
      again
    server exits          -> tmux sends its jobs SIGTERM: exit 0; or the
                             next snapshot finds no server: exit 0
    SIGHUP                -> it runs itself again, on the code now on disk
                             (scripts/update.sh sends it)
    something unexpected  -> exit 1, the reason on stdout, which tmux shows
                             in a pane, and in events.log; no more
                             snapshots until the server starts again

Each run logs to ~/.dotfiles/.logs/<UTC>_tmux_server_arrangement/events.log,
a line per snapshot (or "unchanged") and per session restored or closed.
"""

# A script invoked by path, no license header, as in scripts/.
# ruff: noqa: CPY001

import argparse
import fcntl
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from types import FrameType

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from event_log import EventLog
from tmux_arrangement import (
    NO_SERVER,
    SNAPSHOT_PREFIX,
    ArrangementError,
    idle,
    snapshot_name,
    socket_dir,
    stale_snapshots,
)

STATE = Path.home() / ".local/state/tmux_server_arrangements"
HISTORY_SESSION = "tmux-history"  # scripts/tmux_history.py's: never saved or closed
EVERY = 600.0  # s between snapshots
DEFAULT_SAVE = "all"
TMUX_TIMEOUT = 10  # s for one tmux command; each takes milliseconds
# Fields of a tmux format line: the unit separator, which no session name or
# directory holds in practice; one that does is an error (read_server).
SEP = "\x1f"
NAME = re.compile(r"[A-Za-z0-9_.@+-]+")  # an arrangement name: a file name, no quoting

# A saved arrangement: session -> its windows' directories, in window order.
# Sessions keep the order they were saved in (dicts keep insertion order).
Arrangement = dict[str, list[str]]


class ServerGone(Exception):  # noqa: N818 - an end, not an error
    """No tmux server listens on the socket."""


class Stop(Exception):  # noqa: N818 - a signal, not an error
    """A signal asked the run to stop."""


@dataclass(frozen=True)
class Server:
    """One tmux server, by its socket path."""

    socket: Path

    @property
    def state(self) -> Path:
        """Return where its arrangements live: one folder per socket name."""
        return STATE / self.socket.name

    def tmux(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        """Run one tmux command on this server.

        "no server running" raises ServerGone; any other failure, with
        check, ArrangementError naming the command and what tmux said.
        """
        r = subprocess.run(  # noqa: S603 - tmux, with arguments of our own
            ["tmux", "-S", str(self.socket), *args],  # noqa: S607 - tmux from PATH, as everywhere here
            capture_output=True,
            text=True,
            timeout=TMUX_TIMEOUT,
            check=False,
        )
        if r.returncode != 0 and NO_SERVER.search(r.stderr):
            msg = f"no tmux server on {self.socket}"
            raise ServerGone(msg)
        if check and r.returncode != 0:
            msg = f"tmux {' '.join(args)} on {self.socket} failed: {r.stderr.strip()}"
            raise ArrangementError(msg)
        return r


# --- the file ----------------------------------------------------------------------


def render(arr: Arrangement, header: str) -> str:
    """Return the text of an arrangement, a "# <header>" line first."""
    lines = [f"# {header}"]
    for session, windows in arr.items():
        lines.append(f"session {session}")
        lines.extend(f"  window {d}" for d in windows)
    return "\n".join(lines) + "\n"


def parse(text: str, where: str) -> Arrangement:
    """Read an arrangement; raise ArrangementError naming `where` and the line.

    Comments and blank lines are skipped. Everything else is "session <name>"
    or "window <directory>" (leading spaces allowed), the value being the rest
    of the line as it stands: a directory may end in a space.
    """
    arr: Arrangement = {}
    session = None
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.lstrip(" ")
        if not line or line.startswith("#"):
            continue
        keyword, _, value = line.partition(" ")
        if keyword == "session" and value:
            if value in arr:
                msg = f"{where}:{n}: session {value!r} a second time"
                raise ArrangementError(msg)
            session = value
            arr[session] = []
        elif keyword == "window" and value.startswith("/"):
            if session is None:
                msg = f"{where}:{n}: a window before any session"
                raise ArrangementError(msg)
            arr[session].append(value)
        else:
            msg = (
                f"{where}:{n}: {raw!r} is neither 'session <name>' nor"
                " 'window <absolute directory>'"
            )
            raise ArrangementError(msg)
    empty = [s for s, windows in arr.items() if not windows]
    if empty:
        msg = f"{where}: session(s) with no window: {', '.join(empty)}"
        raise ArrangementError(msg)
    return arr


def body(text: str) -> str:
    """Return an arrangement's text without its comment lines: what it holds."""
    return "\n".join(x for x in text.splitlines() if not x.startswith("#"))


def write(path: Path, text: str) -> None:
    """Write `text` to `path` whole or not at all: a temp file renamed into place."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def names(directory: Path) -> list[str]:
    """Return the arrangements saved in `directory`, by name."""
    return sorted(p.stem for p in directory.glob("*.txt")) if directory.is_dir() else []


def check_name(name: str) -> str:
    """Return `name` if it can name a file here; else raise ArrangementError."""
    if not NAME.fullmatch(name):
        msg = f"arrangement name {name!r}: use letters, digits and _.@+- only"
        raise ArrangementError(msg)
    return name


def snapshot_time(name: str) -> datetime | None:
    """Return when snapshot `name` was taken, None for a name of another kind."""
    if not name.startswith(SNAPSHOT_PREFIX):
        return None
    stamp = name.removeprefix(SNAPSHOT_PREFIX)
    try:
        return datetime.strptime(stamp, "%Y%m%d_%H%M%S").replace(tzinfo=UTC)
    except ValueError as e:
        msg = (
            f"arrangement {name!r} has the snapshot prefix but no"
            " YYYYMMDD_HHMMSS time after it; rename or remove it"
        )
        raise ArrangementError(msg) from e


def default_restore(saved: list[str], started: datetime | None) -> str:
    """Return the snapshot restore picks: the newest taken before `started`.

    The server's start, or None with no server running (then the newest of
    all). After a reboot the snapshots taken since are of the new server,
    so the old server's last one is the one wanted.

        auto-..._0950, auto-..._1000 | server starts 10:05 | auto-..._1015
        -> auto-..._1000
    """
    before = [
        (when, n)
        for n in saved
        if (when := snapshot_time(n)) is not None
        and (started is None or when < started)
    ]
    if not before:
        since = (
            ""
            if started is None
            else f" before this server started ({started:%Y-%m-%d %H:%M:%S}Z)"
        )
        msg = (
            f"no snapshot{since}; `list` shows what there is,"
            " `restore <name>` takes one"
        )
        raise ArrangementError(msg)
    return max(before)[1]


# --- the server --------------------------------------------------------------------


def read_server(server: Server) -> Arrangement:
    """Return what the server holds now, tmux-history left out.

    list-windows -a -> "api<US>0<US>/home/me/src/api" per window
    -> {"api": ["/home/me/src/api", ...], ...}, windows by index
    """
    fmt = SEP.join(["#{session_name}", "#{window_index}", "#{pane_current_path}"])
    out = server.tmux("list-windows", "-a", "-F", fmt).stdout
    rows = []
    for line in out.splitlines():
        fields = line.split(SEP)
        if len(fields) != 3:  # noqa: PLR2004 - the three fields of fmt
            msg = (
                f"a window of {server.socket} reads {line!r}:"
                " a name or directory holds a control character"
            )
            raise ArrangementError(msg)
        session, index, directory = fields
        if session != HISTORY_SESSION:
            rows.append((session, int(index), directory))
    arr: Arrangement = {}
    for session, _, directory in sorted(rows, key=lambda r: (r[0], r[1])):
        arr.setdefault(session, []).append(directory)
    return arr


def server_started(server: Server) -> datetime | None:
    """Return when the server started, None if none is running."""
    try:
        out = server.tmux("display-message", "-p", "#{start_time}").stdout
    except ServerGone:
        return None
    return datetime.fromtimestamp(int(out.strip()), UTC)


def take(server: Server, name: str, log: EventLog) -> Path | None:
    """Save the server as `name`; a snapshot only if it changed; return the file.

    None for a snapshot not written: the server holds nothing to save, or
    the newest snapshot holds the same.
    """
    arr = read_server(server)
    snapshot = name.startswith(SNAPSHOT_PREFIX)
    windows = sum(len(w) for w in arr.values())
    if not arr:
        if snapshot:
            log.note("snapshot: no session to save; none written")
            return None
        msg = f"{server.socket} holds no session to save"
        raise ArrangementError(msg)
    text = render(
        arr,
        f"tmux_server_arrangement.py: {server.socket},"
        f" {datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ}",
    )
    saved = names(server.state)
    if snapshot:
        newest = max((n for n in saved if n.startswith(SNAPSHOT_PREFIX)), default=None)
        last = server.state / f"{newest}.txt" if newest else None
        if last and body(last.read_text(encoding="utf-8")) == body(text):
            log.note(f"snapshot: unchanged since {newest}; none written")
            return None
    path = server.state / f"{name}.txt"
    write(path, text)
    log.note(f"saved {path}: {len(arr)} sessions, {windows} windows")
    if snapshot:
        for stale in stale_snapshots([*saved, name], server.state):
            (server.state / f"{stale}.txt").unlink()
            log.note(f"removed {stale}, past the newest kept")
    return path


# --- restore and replace -----------------------------------------------------------


def load(server: Server, name: str | None) -> tuple[str, Arrangement]:
    """Return the arrangement `name` (restore's default if None) and its name."""
    saved = names(server.state)
    if name is None:
        name = default_restore(saved, server_started(server))
    path = server.state / f"{check_name(name)}.txt"
    if not path.is_file():
        msg = f"no arrangement {name!r} in {server.state}; `list` shows what there is"
        raise ArrangementError(msg)
    return name, parse(path.read_text(encoding="utf-8"), str(path))


def live_sessions(server: Server) -> list[str]:
    """Return the sessions open on the server, none if no server runs."""
    try:
        out = server.tmux("list-sessions", "-F", "#{session_name}").stdout
    except ServerGone:
        return []
    return out.splitlines()


def plan_restore(arr: Arrangement, live: list[str]) -> tuple[Arrangement, list[str]]:
    """Return the sessions to create, and those left as they are (already open).

    A directory gone from a session to create is an error before anything
    opens, every such directory named.
    """
    create = {s: w for s, w in arr.items() if s not in live}
    kept = [s for s in arr if s in live]
    gone = [
        f"{s}: {d}"
        for s, windows in create.items()
        for d in windows
        if not Path(d).is_dir()
    ]
    if gone:
        msg = (
            "directories gone, so nothing was restored"
            " (edit the arrangement, or make them):\n  " + "\n  ".join(gone)
        )
        raise ArrangementError(msg)
    return create, kept


def create(server: Server, create: Arrangement, log: EventLog) -> None:
    """Make each session, a window per directory, its first window selected.

    One tmux command per window, not a ";" chain: tmux reads an argument
    ending in ";" as a separator, and a directory may end in one.
    """
    for session, windows in create.items():
        server.tmux("new-session", "-d", "-s", session, "-c", windows[0])
        for d in windows[1:]:
            server.tmux("new-window", "-d", "-t", f"={session}:", "-c", d)
        log.note(f"restored {session}: {len(windows)} windows")


def restore(server: Server, name: str | None, log: EventLog) -> None:
    """Restore arrangement `name` beside the sessions open."""
    name, arr = load(server, name)
    todo, kept = plan_restore(arr, live_sessions(server))
    log.note(f"restore {name}: {len(todo)} to create, {len(kept)} already open")
    for s in kept:
        log.note(f"left {s} as it is: already open")
    create(server, todo, log)


def own_session(server: Server) -> str | None:
    """Return the session this command runs in on `server`, None if not in one.

    $TMUX is "<socket>,<pid>,<session id>"; $TMUX_PANE the pane.
    """
    tmux_env, pane = os.environ.get("TMUX", ""), os.environ.get("TMUX_PANE", "")
    if (
        not tmux_env
        or not pane
        or Path(tmux_env.split(",")[0]).resolve() != server.socket.resolve()
    ):
        return None
    shown = server.tmux("display-message", "-p", "-t", pane, "#{session_name}")
    return shown.stdout.strip()


def foreground(pid: str) -> str:
    """Return the command line in the foreground of the tty of pane process `pid`.

    ps's tpgid is the tty's foreground process group, and its id the pid of
    the group's leader: the shell at its prompt, or what it runs.

        pane fish 1000, at its prompt   -> tpgid 1000 -> "fish"
        fish 1000 runs claude, 1200     -> tpgid 1200 -> "claude -n vm/api"
        pane `bash build.sh` itself     -> tpgid 1000 -> "bash build.sh"

    A process gone between the two reads is an error: run it again.
    """
    tpgid = ps(pid, "tpgid")
    return ps(tpgid, "args")


def ps(pid: str, field: str) -> str:
    """Return one ps field of process `pid`; raise ArrangementError if it is gone."""
    r = subprocess.run(  # noqa: S603 - ps, with arguments of our own
        ["ps", "-o", f"{field}=", "-p", pid],  # noqa: S607 - ps from PATH
        capture_output=True,
        text=True,
        timeout=TMUX_TIMEOUT,
        check=False,
    )
    if r.returncode != 0 or not r.stdout.strip():
        msg = (
            f"ps -o {field}= -p {pid}: no such process (it ended meanwhile?); run again"
        )
        raise ArrangementError(msg)
    return r.stdout.strip()


def busy_panes(server: Server, sessions: list[str]) -> list[str]:
    """Return the panes of `sessions` whose foreground is not an idle shell.

    The whole command line, as idle() reads it (tmux_arrangement.py): a
    shell alone, "fish" or "-zsh", is at its prompt; "bash build.sh" runs a
    script, though tmux names it "bash" all the same.

        ["main:0.0 claude -n vm/main", "solo:1.0 bash build.sh"]

    Not seen: a job a shell put in the background (`cmd &`), as the shell is
    in the foreground again; closing the session ends it.
    """
    fields = ["#{session_name}", "#{window_index}.#{pane_index}", "#{pane_pid}"]
    busy = []
    for line in server.tmux(
        "list-panes",
        "-a",
        "-F",
        SEP.join(fields),
    ).stdout.splitlines():
        session, pane, pid = line.split(SEP)
        if session in sessions and not idle(command := foreground(pid)):
            busy.append(f"{session}:{pane} {command}")
    return busy


def replace(server: Server, name: str | None, log: EventLog) -> None:
    """Restore arrangement `name`, then close every session it does not hold."""
    name, arr = load(server, name)
    live = live_sessions(server)
    close = [s for s in live if s not in arr and s != HISTORY_SESSION]
    own = own_session(server)
    if own in close:
        msg = (
            f"refused: this runs in session {own!r}, which replace would close;"
            " run it from another session or outside tmux"
        )
        raise ArrangementError(msg)
    busy = busy_panes(server, close)
    if busy:
        msg = (
            "refused: closing these would end what runs in them"
            " (quit it, or restore instead):\n  " + "\n  ".join(busy)
        )
        raise ArrangementError(msg)
    todo, kept = plan_restore(arr, live)
    log.note(
        f"replace {name}: {len(todo)} to create, {len(kept)} already open,"
        f" {len(close)} to close",
    )
    create(server, todo, log)
    for s in close:
        server.tmux("kill-session", "-t", f"={s}")
        log.note(f"closed {s}: not in {name}")


def list_saved(server: Server) -> None:
    """Print each arrangement, its sessions and windows, and restore's pick."""
    saved = names(server.state)
    try:
        pick = default_restore(saved, server_started(server))
    except ArrangementError:
        pick = None
    for n in saved:
        arr = parse((server.state / f"{n}.txt").read_text(encoding="utf-8"), n)
        mark = "  <- restore's default" if n == pick else ""
        windows = sum(len(w) for w in arr.values())
        print(f"{n}  {len(arr)} sessions, {windows} windows{mark}")  # noqa: T201
    if not saved:
        print(f"nothing saved in {server.state}")  # noqa: T201


# --- run: a snapshot every 10 minutes ----------------------------------------------


def run(server: Server, every: float, log: EventLog) -> str:
    """Snapshot every `every` s until the server ends; return why it stopped.

        "SIGTERM", "SIGINT", "SIGHUP"   the signal that stopped it
        ""                              a snapshot found the server gone
        "duplicate"                     another run holds the server's lock

    The lock is the file's flock, held for the process's life: it goes with
    the process however that ends, kill -9 included, and an exec (SIGHUP)
    closes it, so the run started again takes it afresh.
    """
    server.state.mkdir(parents=True, exist_ok=True)
    lock = (server.state / ".run.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return "duplicate"

    def stop(signum: int, _frame: FrameType | None) -> None:
        raise Stop(signal.Signals(signum).name)

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, stop)
    try:
        while True:
            time.sleep(every)
            try:
                take(server, snapshot_name(datetime.now(UTC)), log)
            except ServerGone:
                return ""
    except Stop as e:
        return str(e)


def run_main(server: Server, every: float) -> int:
    """Run the snapshots for the server: `run`, and what wraps it."""
    # stdout is the job's, and tmux shows it on screen when the job ends.
    log = EventLog.start("tmux_server_arrangement", echo=None)
    log.note(
        f"run {os.getpid()} starting: socket {server.socket},"
        f" a snapshot every {every:g} s",
    )
    try:
        ended = run(server, every, log)
    except Exception as e:
        log.note(f"FAILED: {type(e).__name__}: {e}")
        print(  # noqa: T201
            f"tmux_server_arrangement.py: snapshots of {server.socket}"
            f" FAILED: {e} (log: {log.path})",
        )
        raise
    if ended == "duplicate":
        log.note("another run holds this server's lock; exiting")
    elif ended == "SIGHUP":
        log.note("running again, on the code now on disk")
        os.execv(sys.argv[0], sys.argv)  # noqa: S606 - this script, as it was run
    else:
        log.note(f"stopped: {ended or 'the server is gone'}")
    return 0


# --- main --------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    """Run the verb argv names."""
    # The server, given after the verb ("restore -L work"), as tmux.conf's
    # "run -S <socket>" has it.
    server_opts = argparse.ArgumentParser(add_help=False)
    where = server_opts.add_mutually_exclusive_group()
    where.add_argument(
        "-L",
        dest="name",
        default="default",
        help="the server's socket name (default: default)",
    )
    where.add_argument("-S", dest="path", help="the server's socket path")
    p = argparse.ArgumentParser(
        prog="tmux_server_arrangement.py",
        description=__doc__.split("\n")[0],
    )
    sub = p.add_subparsers(dest="verb", required=True)

    def verb(name: str, what: str) -> argparse.ArgumentParser:
        return sub.add_parser(name, help=what, parents=[server_opts])

    verb("snapshot", "the server now, as auto-<UTC time>, unless unchanged")
    for name, what in (
        ("save", f"the server now, as <name> (default {DEFAULT_SAVE})"),
        ("restore", "the saved sessions, beside what is open"),
        ("replace", "the saved sessions, in place of every session open"),
    ):
        verb(name, what).add_argument("arrangement", nargs="?")
    verb("list", "the arrangements saved, and restore's default")
    r = verb(
        "run",
        "a snapshot every 10 minutes, until the server ends (tmux.conf runs this)",
    )
    r.add_argument(
        "--every",
        type=float,
        default=EVERY,
        help=f"seconds between snapshots (default {EVERY:g})",
    )
    args = p.parse_args(argv)
    server = Server(Path(args.path) if args.path else socket_dir() / args.name)

    if args.verb == "run":
        return run_main(server, args.every)
    if args.verb == "list":
        list_saved(server)
        return 0
    log = EventLog.start("tmux_server_arrangement")
    try:
        if args.verb == "snapshot":
            take(server, snapshot_name(datetime.now(UTC)), log)
        elif args.verb == "save":
            take(server, check_name(args.arrangement or DEFAULT_SAVE), log)
        elif args.verb == "restore":
            restore(server, args.arrangement, log)
        else:
            replace(server, args.arrangement, log)
    except (ArrangementError, ServerGone) as e:
        log.note(f"FAILED: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

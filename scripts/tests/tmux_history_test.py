"""tmux_history.py: what tmux reports in, each session's stays, prefix C-s answered.

pure      %session-window-changed, list-sessions --> stays (Tracker)
          %paste-buffer-changed --> show-buffer --> answer() --> select-window
end to    trackers as tmux.conf starts them (its own lines, cut out), on
end       throwaway servers in a socket folder of their own (TMUX_TMPDIR)
          and a throwaway HOME, with clients in ptys that send what a
          terminal sends (prefix C-s):

  server starts, a client on   -> its tracker connects; the tracker sits in
    "api work" window 1           session tmux-history, attached there alone,
                                  ignore-size, not read-only
  prefix C-s, nothing stayed   -> told so, the window unchanged
    in before
  1.5 s in window 1, 0.3 s in  -> back to 1, past 0; again: to 2; window 1
    0, 1.5 s in 2, prefix C-s     closed: told so (0 was passed through)
  tmux.conf sourced again      -> a second tracker finds tmux-history there
                                  and exits; still one
  tmux-history killed          -> reconnects into a new tmux-history
  SIGHUP                       -> runs itself again, same pid, connects
  a second server (-L work),   -> a tracker of its own; killed (-9): its
    its tracker killed            tmux-history goes with it, the first
                                  tracker still connected
  the other sessions closed    -> it kills tmux-history, the server exits
                                  (exit-empty), the tracker with it
  a tracker that cannot start  -> exit 1, the reason in events.log and on
    (a tmux that cannot run)      screen (a pane in view-mode)
  keys sent from outside tmux  -> they arrive: tmux refuses send-keys
    (a script's send-keys), the   for a read-only latest client, so the
    tracker the only client       tracker's is not one
  a server on a path of its    -> no tracker; prefix C-s says there is
    own (-S)                      none, and leaves no buffer

python3 tmux_history_test.py <repo> <event log>
"""

# A test script, not a package: asserts are its checks.
# Each check is named for what it shows, so its name is its docstring.
# ruff: noqa: S101, INP001, CPY001, D103, PLR2004, S603

import fcntl
import importlib.util
import os
import pty
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
from collections.abc import Callable
from pathlib import Path

REPO, LOG = Path(sys.argv[1]), Path(sys.argv[2])
SCRIPT = REPO / "scripts/tmux_history.py"
spec = importlib.util.spec_from_file_location("tmux_history", SCRIPT)
assert spec
assert spec.loader
th = importlib.util.module_from_spec(spec)
spec.loader.exec_module(th)
Reply, Pending = th.Reply, th.Pending
log = th.EventLog(LOG.open("a", buffering=1, encoding="utf-8"), sys.stdout).note
NOWHERE = "no other window of this session to go back to"  # the key's message


class Notes:
    """An EventLog stand-in: keeps the lines, and what was sent to tmux."""

    def __init__(self) -> None:
        """Start with no lines, and no command sent."""
        self.lines: list[str] = []
        self.sent: list[str] = []

    def note(self, line: str) -> None:
        """Keep the line, as EventLog.note writes it."""
        self.lines.append(line)


def tracker() -> tuple[th.Tracker, Notes]:
    """Return a connected Tracker, no session listed; commands land in notes.sent."""
    notes = Notes()
    tr = th.Tracker(notes, notes.sent.append)  # type: ignore[arg-type]
    tr.connect(Reply(()))
    assert notes.sent == [th.LIST], notes.sent
    assert tr.handle(Reply(())) is None  # OWN, sent with the attach
    tr.pending.popleft()  # LIST, answered below at a time of the test's own
    # LIST: the tracker's own session, and one no test uses, so there is
    # more than one; placed at 0, before any test's times.
    tr.sessions_listed(("$0 @0", "$9 @9"), 0)
    notes.sent.clear()
    return tr, notes


def raised(fn: Callable[[], object], kind: type[Exception] | None = None) -> str:
    """Return what `fn` raised, a TrackerError unless `kind` says; fail if none."""
    kind = kind or th.TrackerError
    try:
        fn()
    except kind as e:
        return str(e)
    msg = f"no {kind.__name__}"
    raise AssertionError(msg)


def stays(tr: th.Tracker, session: str = "$1") -> list[tuple[str, float, float]]:
    return [(s.window_id, s.start, s.end) for s in tr.stays.get(session, ())]


# --- the pure part -------------------------------------------------------------


def test_parse_listed_and_parse_ask_read_their_lines_and_refuse_others() -> None:
    assert th.parse_listed("$3 @4") == ("$3", "@4")
    assert "not '$<session> @<window>'" in raised(lambda: th.parse_listed("@4 $3"))
    assert th.parse_ask("/dev/pts/3 $3:@4") == ("/dev/pts/3", "$3", "@4")
    msg = raised(lambda: th.parse_ask("/dev/pts/3 @4"))
    assert "not '<client> $<session>:@<window>'" in msg, msg


def test_read_notifications_yields_every_line_and_reply() -> None:
    lines = iter(
        [
            "%begin 1 1 0",
            "%end 1 1 0",  # the attach: ready
            "%session-window-changed $3 @2",
            "%begin 2 2 1",
            "%end 2 2 1",  # an empty reply is a reply too
            "%begin 3 3 1",
            "$3 @2",
            "%end 3 3 1",
            "%begin 4 4 1",
            "no buffer tmux-history-ask",
            "%error 4 4 1",
        ],
    )
    assert list(th.read_notifications(lines)) == [
        Reply(()),
        "%session-window-changed $3 @2",
        Reply(()),
        Reply(("$3 @2",)),
        Reply(("no buffer tmux-history-ask",), ok=False),
    ]


def test_a_stay_is_a_second_or_more_in_one_window_of_one_session() -> None:
    tr, notes = tracker()
    for t, session, window in (
        (100, "$1", "@1"),
        (130, "$1", "@2"),  # 30 s in @1: a stay
        (130.4, "$1", "@3"),  # 0.4 s in @2: passed through
        (140, "$2", "@7"),  # another session's: $1 stays at @3
        (150, "$1", "@3"),  # no change
        (160, "$1", "@1"),
    ):
        tr.window_changed(session, window, t)
    assert stays(tr) == [("@1", 100, 130), ("@3", 130.4, 160)], stays(tr)
    assert stays(tr, "$2") == [], stays(tr, "$2")
    assert notes.lines[-1] == "$1 at @1", notes.lines


def test_the_list_places_sessions_and_forgets_the_ones_gone() -> None:
    tr, notes = tracker()
    tr.sessions_listed(("$0 @0", "$1 @1", "$2 @7"), 100)
    tr.window_changed("$1", "@2", 110)
    tr.window_changed("$2", "@8", 120)
    # $1 switched to @3 while the list was on its way; $2 closed.
    tr.sessions_listed(("$0 @0", "$1 @3"), 130)
    assert stays(tr) == [("@1", 100, 110), ("@2", 110, 130)], stays(tr)
    assert "$2" not in tr.stays, tr.stays
    assert "$2" not in tr.current, tr.current
    assert "$2 gone" in notes.lines, notes.lines
    # The sessions changing asks for the list again.
    tr.handle("%sessions-changed")
    assert notes.sent == [th.LIST], notes.sent


def test_prefix_c_s_reads_the_buffer_then_goes_back_in_its_session() -> None:
    tr, notes = tracker()
    for t, session, window in (
        (100, "$1", "@1"),
        (110, "$1", "@2"),
        (110.3, "$1", "@3"),  # @2 passed through
        (120, "$2", "@7"),
        (125, "$2", "@8"),
    ):
        tr.window_changed(session, window, t)

    def press(at: str) -> str:
        notes.sent.clear()
        tr.handle("%paste-buffer-changed tmux-history-ask")
        assert notes.sent == [
            "show-buffer -b tmux-history-ask",
            "delete-buffer -b tmux-history-ask",
        ], notes.sent
        tr.handle(Reply((f"p1 {at}",)))
        tr.handle(Reply(()))  # delete-buffer
        (answer,) = notes.sent[2:]
        tr.handle(Reply(()))  # the answer landed: logged
        return answer

    assert press("$1:@3") == "select-window -t '$1:@1'"
    assert notes.lines[-1].startswith("p1 at $1:@3: to $1:@1, left "), notes.lines
    assert press("$2:@8") == "select-window -t '$2:@7'"
    message = f"display-message -c 'p1' 'tmux history: {NOWHERE}'"
    assert press("$3:@9") == message
    # A window closed: its stays go, and nothing in $1 is left but @3.
    tr.handle("%unlinked-window-close @1")
    assert press("$1:@3") == message
    # Another buffer changing is none of the tracker's business.
    notes.sent.clear()
    tr.handle("%paste-buffer-changed buffer0")
    assert notes.sent == [], notes.sent


def test_errors_raise_for_the_tracker_s_own_commands_and_are_logged_for_a_press() -> (
    None
):
    tr, notes = tracker()
    # Two presses read as one: the second show-buffer finds no buffer.
    tr.handle("%paste-buffer-changed tmux-history-ask")
    tr.handle(Reply(("no buffer tmux-history-ask",), ok=False))
    tr.handle(Reply(()))
    assert notes.lines[-1].startswith("FAILED to read the ask: show-buffer"), (
        notes.lines
    )
    # A switch to a window gone in between: logged, the tracker goes on.
    tr.command(Pending("answer", "select-window -t '$1:@1'", note="to @1"))
    tr.handle(Reply(("can't find window: @1",), ok=False))
    assert notes.lines[-1].startswith("FAILED to to @1: select-window"), notes.lines
    tr.command(Pending("sessions", th.LIST))
    msg = raised(lambda: tr.handle(Reply(("bad",), ok=False)))
    assert "tmux refused a tracker command: list-sessions" in msg, msg
    msg = raised(lambda: tr.handle(Reply(("what",))))
    assert "a command reply the tracker did not ask for" in msg, msg


def test_the_attach_refused_raises_and_a_second_tracker_gives_way() -> None:
    notes = Notes()
    tr = th.Tracker(notes, notes.sent.append)  # type: ignore[arg-type]
    duplicate = Reply(("duplicate session: tmux-history",), ok=False)
    msg = raised(lambda: tr.connect(duplicate), th.Tracked)
    assert "tracked already" in msg, msg
    msg = raised(lambda: tr.connect(Reply(("bad flag",), ok=False)))
    assert "tmux refused the attach: bad flag" in msg, msg
    msg = raised(lambda: tr.connect("%sessions-changed"))
    assert "not the reply to the attach" in msg, msg
    assert notes.sent == [], notes.sent


def test_the_last_session_left_ends_the_connection_for_good() -> None:
    tr, _ = tracker()
    tr.handle("%sessions-changed")
    end = tr.handle(Reply(("$0 @0",)))
    assert end == th.End(
        "tmux-history is the last session; leaving, so the server exits",
        again=False,
    ), end
    assert tr.handle("%session-changed $9 elsewhere") == th.End(
        "moved out of tmux-history to $9 elsewhere",
        again=True,
    )


# --- end to end ------------------------------------------------------------------

WORK = Path(tempfile.mkdtemp(prefix="tmux_history_test."))
HOME = WORK / "home"
# Unix socket paths are capped near 104 bytes: the socket folder is short.
SOCKETS = Path(tempfile.mkdtemp(prefix="thtest.", dir="/tmp"))
SOCKET_DIR = SOCKETS / f"tmux-{os.getuid()}"
LOGS = HOME / ".dotfiles/.logs"
CONF = WORK / "tmux.conf"
TMUX = shutil.which("tmux") or "tmux"
# The servers' environment, which their run-shell jobs inherit: the
# throwaway HOME, where the trackers' logs land, and tmux's socket folder.
ENV = {
    **{k: v for k, v in os.environ.items() if k not in {"TMUX", "TMUX_TMPDIR"}},
    "HOME": str(HOME),
    "TMUX_TMPDIR": str(SOCKETS),
}
PREFIX_C_S = b"\x02\x13"  # C-b, then C-s, as typed


def conf_part(start: str, end: str) -> str:
    """Return tmux.conf from the line starting `start` to the next line `end`."""
    lines = (REPO / "home/.config/tmux/tmux.conf").read_text().splitlines()
    (first,) = [i for i, x in enumerate(lines) if x.startswith(start)]
    last = next(i for i in range(first, len(lines)) if lines[i] == end)
    return "\n".join(lines[first : last + 1])


def setup() -> None:
    """Make the throwaway HOME, and the config.

    tmux.conf's own lines, the tracker's and the prefix C-s binding, with
    exit-empty; the prefix stays tmux's C-b.
    """
    (HOME / ".dotfiles").mkdir(parents=True)
    (HOME / ".dotfiles/scripts").symlink_to(REPO / "scripts")
    conf = (REPO / "home/.config/tmux/tmux.conf").read_text().splitlines()
    (run,) = [x for x in conf if "tmux_history.py run" in x and not x.startswith("#")]
    CONF.write_text(
        f"set -g exit-empty on\n{run}\n{conf_part('bind-key C-s ', '}')}\n",
    )


def tmux(
    *args: str,
    server: str = "default",
    argv: list[str] | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run tmux on a test server (-L `server`, or `argv`); return what it did."""
    return subprocess.run(
        [*(argv or [TMUX, "-L", server]), *args],
        env=env or ENV,
        capture_output=True,
        text=True,
        check=False,
    )


def t(*args: str, server: str = "default") -> str:
    """Run tmux on a test server; return its stdout."""
    done = tmux(*args, server=server)
    if done.returncode:
        msg = f"tmux -L {server} {' '.join(args)}: {done.stderr.strip()}"
        raise AssertionError(msg)
    return done.stdout


class Terminal:
    """A tmux client in a pty, written to as a terminal would."""

    def __init__(self, session: str, argv: list[str] | None = None) -> None:
        """Attach a new client to `session`, in a 100x30 pty."""
        argv = argv or [TMUX, "-L", "default"]
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            os.execve(  # noqa: S606 - the pty child becomes tmux, no shell wanted
                argv[0],
                [*argv, "attach", "-t", f"={session}"],
                {**ENV, "TERM": "xterm-256color"},
            )
        self.pid, self.fd = pid, fd
        threading.Thread(target=self.drain, daemon=True).start()

    def drain(self) -> None:
        """Read and drop what tmux draws, so it never blocks on a full pty."""
        while True:
            try:
                if not os.read(self.fd, 65536):
                    return
            except OSError:
                return

    def send(self, data: bytes) -> None:
        """Write bytes as the terminal would send them."""
        os.write(self.fd, data)

    def close(self) -> None:
        """End the client, as a closed terminal tab does."""
        os.kill(self.pid, signal.SIGTERM)
        os.waitpid(self.pid, 0)


def shown(client: str) -> str:
    """Return what the client shows: "<session>:<window index>"."""
    out = t("list-clients", "-F", "#{client_name}\t#{client_session}:#{window_index}")
    return dict(line.split("\t") for line in out.splitlines())[client]


def tracker_log() -> str:
    """Return the trackers' logs, oldest first."""
    return "".join(
        p.read_text() for p in sorted(LOGS.glob("*_tmux_history*/events.log"))
    )


def trackers(server: str) -> list[int]:
    """Return the pids the logs show starting for `server`, oldest first."""
    socket = re.escape(str(SOCKET_DIR / server))
    return [
        int(m[1])
        for m in re.finditer(
            rf"tracker (\d+) starting: socket {socket}$",
            tracker_log(),
            re.MULTILINE,
        )
    ]


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def until(what: str, ok: Callable[[], bool], seconds: float = 10) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if ok():
            return
        time.sleep(0.05)
    msg = f"{what}: not within {seconds:g}s; log:\n{tracker_log()}"
    raise AssertionError(msg)


def attached(session: str, server: str = "default") -> str:
    """Return the session's attached-client count, "" if there is no such session."""
    out = t(
        "list-sessions",
        "-F",
        "#{session_name}\t#{session_attached}",
        server=server,
    )
    return dict(line.split("\t") for line in out.splitlines()).get(session, "")


def control_clients(server: str = "default") -> list[str]:
    out = t(
        "list-clients",
        "-F",
        "#{client_flags}",
        "-f",
        "#{client_control_mode}",
        server=server,
    )
    return out.splitlines()


def no_server(server: str = "default") -> bool:
    """Tell whether no server listens; its socket file outlives it."""
    done = tmux("-N", "list-sessions", server=server)
    return done.returncode != 0 and "no server running" in done.stderr


def moves() -> list[str]:
    """Return where each prefix C-s pressed so far went, NOWHERE if nowhere."""
    found = re.findall(r" at \S+: (to [^,\s]+|" + NOWHERE + ")", tracker_log())
    return [m.removeprefix("to ") for m in found]


def run_end_to_end() -> None:  # noqa: PLR0915 - one story, step by step
    setup()
    terms: list[Terminal] = []
    try:
        t("-f", str(CONF), "new-session", "-d", "-s", "api work", "sleep 600")
        for _ in range(2):
            t("new-window", "-d", "-t", "=api work:", "sleep 600")
        t("select-window", "-t", "=api work:1")
        t("new-session", "-d", "-s", "docs|x", "sleep 600")  # a name to quote
        terms.append(Terminal("api work"))
        until("the sessions placed", lambda: "connected: control" in tracker_log())
        until(
            "a session placed",
            lambda: (
                re.search(r"\$\d+ at @\d+$", tracker_log(), re.MULTILINE) is not None
            ),
        )
        (human,) = t(
            "list-clients",
            "-F",
            "#{client_name}",
            "-f",
            "#{?client_control_mode,0,1}",
        ).split()
        (flags,) = control_clients()
        assert all(f in flags for f in ("ignore-size", "no-output")), flags
        assert "read-only" not in flags, flags
        assert attached("tmux-history") == "1", attached("tmux-history")
        (pid,) = trackers("default")
        passed("the server starts its tracker; it sits apart, attached alone")

        def press(n: int) -> None:
            terms[0].send(PREFIX_C_S)
            until(f"press {n} answered", lambda: len(moves()) == n)

        def window(index: int) -> str:
            return t(
                "display",
                "-p",
                "-t",
                f"=api work:{index}",
                "#{window_id}",
            ).strip()

        press(1)
        assert moves() == [NOWHERE], moves()
        assert shown(human) == "api work:1", shown(human)
        passed("prefix C-s with nothing stayed in before: told so")

        w1, w2 = window(1), window(2)
        time.sleep(1.5)
        t("select-window", "-t", "=api work:0")
        time.sleep(0.3)
        t("select-window", "-t", "=api work:2")
        time.sleep(1.5)
        press(2)
        until("back in window 1, past 0", lambda: shown(human) == "api work:1")
        press(3)
        until("window 2 again", lambda: shown(human) == "api work:2")
        assert [m.split(":")[1] for m in moves()[1:]] == [w1, w2], moves()
        passed("prefix C-s: back to the last window stayed in, past one passed through")

        t("kill-window", "-t", "=api work:1")
        press(4)
        assert moves()[-1] == NOWHERE, moves()
        assert shown(human) == "api work:2", shown(human)
        assert "FAILED" not in tracker_log(), tracker_log()
        assert not t("list-buffers"), t("list-buffers")
        passed("a window closed since is passed over; the buffer is deleted")

        t("source-file", str(CONF))
        until("the second one gives way", lambda: "tracked already" in tracker_log())
        until("it is gone", lambda: not any(map(alive, trackers("default")[1:])))
        assert len(control_clients()) == 1, control_clients()
        passed("tmux.conf sourced again: the second tracker exits")

        t("kill-session", "-t", "=tmux-history")
        until(
            "reconnects",
            lambda: tracker_log().count(" connected: control client") >= 2,
        )
        until("its session made again", lambda: attached("tmux-history") == "1")
        assert "disconnected: tmux sent %exit" in tracker_log(), tracker_log()
        passed("its session killed: it reconnects into a new one")

        os.kill(pid, signal.SIGHUP)
        until("runs again", lambda: "running again, on the code" in tracker_log())
        until(
            "connects again",
            lambda: tracker_log().count(" connected: control client") >= 3,
        )
        assert trackers("default")[-1] == pid, trackers("default")
        assert len(control_clients()) == 1, control_clients()
        passed("SIGHUP: it runs itself again, same pid, and reconnects")

        t("-f", str(CONF), "new-session", "-d", "-s", "api", "sleep 600", server="work")
        until("the work server's tracker", lambda: len(trackers("work")) == 1)
        until("it connects", lambda: len(control_clients("work")) == 1)
        (work_pid,) = trackers("work")
        os.kill(work_pid, signal.SIGKILL)
        until(
            "its session goes with it",
            lambda: attached("tmux-history", server="work") == "",
        )
        t("kill-server", server="work")
        assert alive(pid), tracker_log()
        assert len(control_clients()) == 1, control_clients()
        passed(
            "a second server: a tracker of its own, killed -9: its session goes;"
            " the first one carries on",
        )

        for session in ("api work", "docs|x"):
            t("kill-session", "-t", f"={session}")
        until("leaves", lambda: "is the last session; leaving" in tracker_log())
        until("the server exits", no_server)
        until("the tracker exits", lambda: not alive(pid))
        passed("the other sessions closed: it leaves, the server exits, it too")
    finally:
        for term in terms:
            term.close()
        for server in ("default", "work"):
            tmux("kill-server", server=server)


def run_failure() -> None:
    """Start a tracker that cannot go on; it must fail where tmux shows it.

    The server's run-shell job finds, first on PATH, a tmux that only
    complains: the tracker's control client exits before connecting.
    """
    fake = WORK / "fake-bin"
    fake.mkdir()
    (fake / "tmux").write_text("#!/bin/sh\necho 'fake tmux: refusing' >&2\nexit 1\n")
    (fake / "tmux").chmod(0o755)
    done = tmux(
        "-f",
        str(CONF),
        "new-session",
        "-d",
        "-s",
        "b",
        "sleep 600",
        server="bad",
        env={**ENV, "PATH": f"{fake}:{ENV['PATH']}"},
    )
    assert done.returncode == 0, done.stderr
    try:
        until("it fails", lambda: "FAILED" in tracker_log())
        assert "fake tmux: refusing" in tracker_log(), tracker_log()
        until(
            "the reason on screen",
            lambda: (
                t("display", "-p", "-t", "=b:", "#{pane_mode}", server="bad").strip()
                == "view-mode"
            ),
        )
    finally:
        tmux("kill-server", server="bad")


def run_outside_keys() -> None:
    """Send keys from outside tmux to a server only its tracker is attached to.

    A command run outside tmux acts for the server's latest client, here the
    tracker's. tmux refuses send-keys for a read-only one ("client is
    read-only"), which is what the manager's start (claude_manager_start.sh)
    met at boot when the tracker had attached before it typed `claude`.
    """
    t("-f", str(CONF), "new-session", "-d", "-s", "k", "cat", server="keys")
    try:
        until("the tracker's client", lambda: len(control_clients("keys")) == 1)
        assert t("list-clients", "-F", "#{client_name}", server="keys").count("\n") == 1
        t("send-keys", "-t", "=k:0", "-l", "typed outside", server="keys")
        until(
            "the keys in the pane",
            lambda: (
                "typed outside" in t("capture-pane", "-p", "-t", "=k:0", server="keys")
            ),
        )
    finally:
        tmux("kill-server", server="keys")
        # Its last log lines must not land in the next stage's reading.
        until("its tracker gone", lambda: not any(map(alive, trackers("keys"))))


def run_own_socket() -> None:
    """Start a server on a path of its own (-S); no tracker, and the key says so."""
    before = tracker_log()
    argv = [TMUX, "-S", str(SOCKETS / "own")]

    def own(*args: str) -> str:
        done = tmux(*args, argv=argv)
        assert done.returncode == 0, done.stderr
        return done.stdout

    own("-f", str(CONF), "new-session", "-d", "-s", "o", "sleep 600")
    term = Terminal("o", argv)
    try:
        until("the terminal attached", lambda: own("list-clients").strip() != "")
        term.send(PREFIX_C_S)
        until(
            "told there is no tracker",
            lambda: "no tracker on this server" in own("show-messages"),
        )
        assert not own("list-buffers"), own("list-buffers")
        assert tracker_log() == before, tracker_log()[len(before) :]
    finally:
        term.close()
        tmux("kill-server", argv=argv)


# --- runner ----------------------------------------------------------------------

passes = failures = 0


def check(name: str, fn: Callable[[], None]) -> None:
    global passes, failures  # noqa: PLW0603
    try:
        fn()
    except Exception as e:  # noqa: BLE001 - every failure is reported, then counted
        failures += 1
        log(f"FAIL {name}: {type(e).__name__}: {e}")
    else:
        passes += 1
        log(f"PASS {name}")


def passed(name: str) -> None:
    """Count a stage of a story that reached its end: its asserts held."""
    check(name, lambda: None)


for name, fn in list(globals().items()):
    if name.startswith("test_") and callable(fn):
        check(name.removeprefix("test_").replace("_", " "), fn)
check("end to end", run_end_to_end)
check("a tracker that cannot go on: exit 1, the reason on screen", run_failure)
check("keys sent from outside tmux, the tracker the only client", run_outside_keys)
check(
    "a server on a socket path of its own: no tracker, and the key says so",
    run_own_socket,
)
log(f"{passes} passed, {failures} failed")
if failures:
    log(f"kept work dir: {WORK}")
else:
    shutil.rmtree(WORK)
shutil.rmtree(SOCKETS, ignore_errors=True)

"""iterm2_api.py: which bells get a banner and when it closes; what Cmd-T opens.

The real code against a fake iTerm2 app (windows, tabs, focus), with a stub
`iterm2` module so plain python3 runs it, as CI has no uv and no iTerm2:

    fake app (focus, layout) --> Bells.rang / focus_changed / ended,
    fake bellCount monitor   --> watch_session
                                   --> the events it prints, compared
    call times               --> KeyRepeats --> which are repeats
    fake app (jobs)          --> cmd_t --> the tab it opens and what it
                                           types there, or iTerm2's New Tab

    python3 iterm2_api_test.py <repo> <event log>
"""

# A test script, not a package: asserts are its checks.
# ruff: noqa: S101, INP001, CPY001, PLR2004

import asyncio
import contextlib
import importlib.util
import io
import json
import sys
import types
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from typing import Self

REPO, LOG = Path(sys.argv[1]), Path(sys.argv[2])
log_file = LOG.open("a", buffering=1)


def log(msg: str) -> None:
    """Log a UTC-stamped line to the event log and stdout."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    log_file.write(line + "\n")
    print(line, flush=True)  # noqa: T201


# The script imports iterm2 and names its classes in annotations; it
# catches the two API errors that say a session is gone.
class RPCException(Exception):  # noqa: N818 - the package's name
    """Stands in for iterm2.rpc.RPCException."""


class SubscriptionException(Exception):  # noqa: N818 - the package's name
    """Stands in for iterm2.notifications.SubscriptionException."""


class VariableMonitor:
    """Stands in for iterm2.VariableMonitor on a session's bellCount.

    `on_subscribe` runs as it subscribes; async_get hands out `updates`,
    then reports the session gone, which ends watch_session quietly.
    """

    on_subscribe: Callable[[], None] = staticmethod(lambda: None)
    updates: list[str] = []  # noqa: RUF012 - set per case

    def __init__(self, *_: object) -> None:
        """Take the connection, scope, name and session id, unused."""

    async def __aenter__(self) -> Self:
        """Subscribe."""
        VariableMonitor.on_subscribe()
        return self

    async def __aexit__(self, *_: object) -> None:
        """Unsubscribe."""

    async def async_get(self) -> str:
        """Return the next bellCount update."""
        if VariableMonitor.updates:
            return VariableMonitor.updates.pop(0)
        error = "SESSION_NOT_FOUND"
        raise RPCException(error)


stubs = {
    name: types.ModuleType(name)
    for name in ("iterm2", "iterm2.rpc", "iterm2.notifications")
}
vars(stubs["iterm2"]).update(
    {name: type(name, (), {}) for name in ("App", "Session", "Connection")},
    rpc=stubs["iterm2.rpc"],
    notifications=stubs["iterm2.notifications"],
    VariableMonitor=VariableMonitor,
    VariableScopes=types.SimpleNamespace(SESSION="session"),
)
vars(stubs["iterm2.rpc"])["RPCException"] = RPCException
vars(stubs["iterm2.notifications"])["SubscriptionException"] = SubscriptionException
sys.modules.update(stubs)
# The script imports ssh_command.py from its own directory.
sys.path.insert(0, str(REPO / "home/.hammerspoon"))
spec = importlib.util.spec_from_file_location(
    "iterm2_api",
    REPO / "home/.hammerspoon/iterm2_api.py",
)
assert spec
assert spec.loader
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class Session:
    """A session: an id, and variables as the API reads them."""

    def __init__(self, sid: str, name: str) -> None:
        """Make session `sid` named `name`, running a local fish."""
        self.session_id = sid
        self.vars: dict[str, str | None] = {
            "name": name,
            "jobName": "fish",
            "commandLine": "-fish",
            "bellCount": None,  # unset until the first bell
        }
        self.on_read: Callable[[], None] = lambda: None  # runs during the read
        self.typed = ""  # what async_send_text sent

    async def async_get_variable(self, var: str) -> str | None:
        """Read one of the variables the script asks of a session."""
        assert var in self.vars, var
        self.on_read()
        return self.vars[var]

    async def async_send_text(self, text: str) -> None:
        """Type `text` into the session."""
        self.typed += text


class Tab:
    """A tab of sessions (panes)."""

    def __init__(self, *sessions: Session) -> None:
        """Make a tab of `sessions`."""
        self.all_sessions = list(sessions)
        self.current_session = sessions[0]


class Window:
    """A window of tabs, one of them selected."""

    def __init__(self, title: str, *tabs: Tab) -> None:
        """Make a window titled `title`, its first tab selected."""
        self.window_id = f"pty-{title}"
        self.title = title
        self.tabs = list(tabs)
        self.current_tab = tabs[0]

    async def async_get_variable(self, var: str) -> str:
        """Read a variable; only "titleOverride" is asked of a window."""
        assert var == "titleOverride", var
        return self.title

    async def async_create_tab(self) -> Tab:
        """Open a tab at the end, with a fresh local shell, as iTerm2 does."""
        tab = Tab(Session(f"NEW{len(self.tabs)}".ljust(8, "0"), "fish:~"))
        self.tabs.append(tab)
        return tab


class App:
    """The focus and layout the package keeps current."""

    def __init__(self, *windows: Window) -> None:
        """Make an app of `windows`, the first one key and iTerm2 active."""
        self.windows = list(windows)
        self.current_window: Window | None = windows[0]
        self.app_active = True

    def get_session_by_id(self, sid: str) -> Session | None:
        """Find a session in any window by its id."""
        for w in self.windows:
            for t in w.tabs:
                for s in t.all_sessions:
                    if s.session_id == sid:
                        return s
        return None

    def get_window_and_tab_for_session(
        self,
        session: Session,
    ) -> tuple[Window | None, Tab | None]:
        """Find the window and tab that hold `session`; (None, None) if buried."""
        for w in self.windows:
            for t in w.tabs:
                if session in t.all_sessions:
                    return w, t
        return None, None


def events(fn: Callable[[], object]) -> list[dict]:
    """Run `fn` (sync or a coroutine), returning the events it printed."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        result = fn()
        if asyncio.iscoroutine(result):
            asyncio.run(result)
    return [json.loads(line) for line in out.getvalue().splitlines()]


def kinds(evs: list[dict]) -> list[tuple[str, str]]:
    """Reduce events to (event, session) pairs."""
    return [(e["event"], e.get("session", "")) for e in evs]


# Two windows: "dots" (key) with tabs [a | b, c] and "bench" with [d].
def world() -> tuple[App, dict[str, Session], Window, Window]:
    """Build the fake app every case starts from."""
    s = {k: Session(k.upper() * 8, f"name-{k}") for k in "abcd"}
    dots = Window("dots", Tab(s["a"]), Tab(s["b"], s["c"]))
    bench = Window("bench", Tab(s["d"]))
    return App(dots, bench), s, dots, bench


passed = failed = 0


def case(name: str) -> Callable[[Callable[[], None]], None]:
    """Run the decorated function as one case, logging PASS or FAIL."""

    def run(fn: Callable[[], None]) -> None:
        global passed, failed  # noqa: PLW0603
        try:
            fn()
        except Exception as e:  # noqa: BLE001 - a failed case is reported, then the rest run
            failed += 1
            log(f"[{name}] FAIL: {e!r}")
        else:
            passed += 1
            log(f"[{name}] PASS")

    return run


@case("a bell in the tab in view, iTerm2 in front: no banner")
def _() -> None:
    app, s, _, _ = world()
    assert events(lambda: api.Bells(app).rang(s["a"])) == []


@case("a bell in another tab or window: a banner naming it")
def _() -> None:
    app, s, _, _ = world()
    b = api.Bells(app)
    got = events(lambda: b.rang(s["c"])) + events(lambda: b.rang(s["d"]))
    assert got == [
        {
            "event": "bell",
            "session": "CCCCCCCC",
            "name": "name-c",
            "tab": 2,
            "window": "dots",
        },
        {
            "event": "bell",
            "session": "DDDDDDDD",
            "name": "name-d",
            "tab": 1,
            "window": "bench",
        },
    ], got


@case("iTerm2 in the background: even the tab in view gets a banner")
def _() -> None:
    app, s, _, _ = world()
    app.app_active = False
    assert kinds(events(lambda: api.Bells(app).rang(s["a"]))) == [
        ("bell", "AAAAAAAA"),
    ]


@case("every bell before the tab is seen is sent: Hammerspoon keeps one banner")
def _() -> None:
    app, s, _, _ = world()
    b = api.Bells(app)
    assert len(events(lambda: b.rang(s["d"]))) == 1
    assert kinds(events(lambda: b.rang(s["d"]))) == [("bell", "DDDDDDDD")]


@case("the tab comes into view while the bell is read: no banner")
def _() -> None:
    app, s, _, bench = world()
    b = api.Bells(app)

    def switch() -> None:
        app.current_window = bench

    s["d"].on_read = switch
    assert events(lambda: b.rang(s["d"])) == []
    assert "DDDDDDDD" not in b.pending


@case("a bell in the tab in view reads nothing")
def _() -> None:
    app, s, _, _ = world()

    def read() -> None:
        msg = "read a variable for a bell in view"
        raise AssertionError(msg)

    s["a"].on_read = read
    assert events(lambda: api.Bells(app).rang(s["a"])) == []


def watch(app: App, sid: str) -> list[dict]:
    """Watch session `sid`'s bellCount until the fake monitor runs out."""
    return events(lambda: api.watch_session(None, api.Bells(app), sid))


@case("a bell as the watch subscribes is a bell, sent once")
def _() -> None:
    app, s, _, _ = world()

    def ring() -> None:
        s["d"].vars["bellCount"] = "1"
        VariableMonitor.updates = ["1"]

    VariableMonitor.on_subscribe = ring
    try:
        assert kinds(watch(app, "DDDDDDDD")) == [("bell", "DDDDDDDD")]
    finally:
        VariableMonitor.on_subscribe = lambda: None


@case("bellCount rising is a bell; the count it started at, or a repeat, is not")
def _() -> None:
    app, s, _, _ = world()
    s["d"].vars["bellCount"] = "3"
    VariableMonitor.updates = ["4", "4", "6"]
    assert kinds(watch(app, "DDDDDDDD")) == [("bell", "DDDDDDDD")] * 2


@case("a session gone while its bell is read: no banner, no error")
def _() -> None:
    app, s, _, _ = world()

    def vanish() -> None:
        error = "SESSION_NOT_FOUND"
        raise RPCException(error)

    s["d"].on_read = vanish
    assert events(lambda: api.Bells(app).rang(s["d"])) == []


@case("any other API error while a bell is read raises")
def _() -> None:
    app, s, _, _ = world()

    def broken() -> None:
        error = "REQUEST_MALFORMED"
        raise RPCException(error)

    s["d"].on_read = broken
    raised = ""
    try:
        events(lambda: api.Bells(app).rang(s["d"]))
    except RPCException as e:
        raised = str(e)
    assert raised == "REQUEST_MALFORMED", "an unexpected API error was swallowed"


@case("a buried session (in no window) rings: no banner")
def _() -> None:
    app, _, _, _ = world()
    assert events(lambda: api.Bells(app).rang(Session("E" * 8, "buried"))) == []


@case("the banner closes when its tab comes into view, any pane, iTerm2 in front")
def _() -> None:
    app, s, dots, _ = world()
    b = api.Bells(app)
    events(lambda: b.rang(s["b"]))
    events(lambda: b.rang(s["d"]))
    app.app_active = False
    dots.current_tab = dots.tabs[1]
    assert events(b.focus_changed) == [], "seen while iTerm2 was in the background"
    app.app_active = True
    assert kinds(events(b.focus_changed)) == [("seen", "BBBBBBBB")]

    # Seen once, it rings a banner again later.
    dots.current_tab = dots.tabs[0]
    assert kinds(events(lambda: b.rang(s["b"]))) == [("bell", "BBBBBBBB")]


@case("another window becoming key shows its tab")
def _() -> None:
    app, s, _, bench = world()
    b = api.Bells(app)
    events(lambda: b.rang(s["d"]))
    app.current_window = bench
    assert kinds(events(b.focus_changed)) == [("seen", "DDDDDDDD")]


@case("a session that ends closes its banner; one without a banner says nothing")
def _() -> None:
    app, s, _, _ = world()
    b = api.Bells(app)
    events(lambda: b.rang(s["d"]))
    assert kinds(events(lambda: b.ended("DDDDDDDD"))) == [("gone", "DDDDDDDD")]
    assert events(lambda: b.ended("CCCCCCCC")) == []


@case("no key window: nothing is in view")
def _() -> None:
    app, s, _, _ = world()
    app.current_window = None
    assert kinds(events(lambda: api.Bells(app).rang(s["a"]))) == [
        ("bell", "AAAAAAAA"),
    ]


# --- Cmd-T -------------------------------------------------------------------


@case("a held Cmd-T is one press; the next press after a pause is another")
def _() -> None:
    r = api.KeyRepeats(0.417)
    times = [0.0, 0.417, 0.450, 0.483, 2.0, 3.0]
    got = [r.repeat(t) for t in times]
    assert got == [False, True, True, True, False, False], got


def press_cmd_t(app: App, sid: str) -> list[str]:
    """Press Cmd-T in session `sid`; return ["new tab"] if iTerm2's New Tab ran."""
    plain: list[str] = []

    async def plain_new_tab() -> None:
        plain.append("new tab")

    with contextlib.redirect_stderr(io.StringIO()):
        asyncio.run(api.cmd_t(app, sid, plain_new_tab))
    return plain


def ssh_in(session: Session, command_line: str) -> None:
    """Make `session` run ssh with `command_line`."""
    session.vars.update(jobName="ssh", commandLine=command_line)


@case("Cmd-T in an ssh tab: a new tab in that window types the login")
def _() -> None:
    app, s, _, bench = world()
    ssh_in(s["d"], "ssh -p 2222 user@vm")
    assert press_cmd_t(app, "DDDDDDDD") == []
    assert len(bench.tabs) == 2, "no tab opened in the session's own window"
    assert bench.tabs[1].current_session.typed == "ssh -p 2222 user@vm\n"


@case("Cmd-T replays the login only, never the remote command or a forward")
def _() -> None:
    app, s, dots, _ = world()
    ssh_in(s["a"], "ssh -N -L 8080:localhost:80 vm ./deploy.sh")
    press_cmd_t(app, "AAAAAAAA")
    assert dots.tabs[-1].current_session.typed == "ssh vm\n"


@case("Cmd-T in a local tab: iTerm2's own New Tab")
def _() -> None:
    app, _, dots, _ = world()
    assert press_cmd_t(app, "AAAAAAAA") == ["new tab"]
    assert len(dots.tabs) == 2, "a tab was opened besides iTerm2's New Tab"


@case("Cmd-T where the ssh line cannot be replayed safely: iTerm2's New Tab")
def _() -> None:
    app, s, dots, _ = world()
    ssh_in(s["a"], 'ssh -o "ProxyCommand x" vm')
    assert press_cmd_t(app, "AAAAAAAA") == ["new tab"]
    assert len(dots.tabs) == 2


@case("Cmd-T in a session that is gone: nothing, no error")
def _() -> None:
    app, s, dots, _ = world()

    def vanish() -> None:
        error = "SESSION_NOT_FOUND"
        raise RPCException(error)

    s["a"].on_read = vanish
    assert press_cmd_t(app, "AAAAAAAA") == []
    assert press_cmd_t(app, "ZZZZZZZZ") == []
    assert len(dots.tabs) == 2


@case("Cmd-T where iTerm2 reports no jobName raises, never reads as not ssh")
def _() -> None:
    app, s, _, _ = world()
    s["a"].vars["jobName"] = None
    raised = False
    try:
        press_cmd_t(app, "AAAAAAAA")
    except TypeError:
        raised = True
    assert raised, "a missing jobName was taken for a local tab"


log(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

"""iterm2_ssh_arrangement.py: iTerm2's tabs in, saved lines out, or the refusal.

The pure part, with the hosts' `tmux ls` faked and a stub `iterm2` module, so
plain python3 runs it, as CI has no uv, iTerm2 or ssh:

    Tab facts --> plan() --> lines(fake lookup) --> saved lines, compared
    saved windows --> render() --> parse_file() --> the same windows

    python3 iterm2_ssh_arrangement_test.py <repo> <event log>
"""

# A test script, not a package: asserts are its checks.
# ruff: noqa: S101, INP001, CPY001, PLR2004

import asyncio
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import types
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

REPO, LOG = Path(sys.argv[1]), Path(sys.argv[2])
log_file = LOG.open("a", buffering=1)


def log(msg: str) -> None:
    """Log a UTC-stamped line to the event log and stdout."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    log_file.write(line + "\n")
    print(line, flush=True)  # noqa: T201


# The script imports iterm2 and names its classes in annotations.
stub = types.ModuleType("iterm2")
vars(stub).update(
    {n: type(n, (), {}) for n in ("App", "Connection", "Session", "Window")},
)
sys.modules["iterm2"] = stub
# And websockets (iterm2's), for the handshake error `replace` retries.
errors = types.ModuleType("websockets.exceptions")
vars(errors)["InvalidHandshake"] = type("InvalidHandshake", (Exception,), {})
sockets = types.ModuleType("websockets")
vars(sockets)["exceptions"] = errors
sys.modules.update({"websockets": sockets, "websockets.exceptions": errors})
spec = importlib.util.spec_from_file_location(
    "iterm2_ssh_arrangement",
    REPO / "scripts/lib/iterm2_ssh_arrangement.py",
)
assert spec
assert spec.loader
arr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arr)
Tab, Saved, ArrangementError = arr.Tab, arr.Saved, arr.ArrangementError
Landing = arr.Landing
LOCAL = "Mac.local"  # iTerm2's host for a local session here
arr.LOG.append(LOG)  # the script's own log() lines land in this run's log

# What `tmux ls` on each socket of each host prints (list_sessions_argv):
# socket, session, and the name its title shows -- "<hostname>/<session>"
# on the claude socket -- ":"-separated. Twin's claude "dup" shows as "dup"
# through a host named "" -- impossible, but it puts one shown name on both
# sockets.
HOSTS = {
    "ssh vm": "claude:ai-agent:vm/ai-agent\nclaude:api/docs:vm/api/docs\n"
    "default:main:main\n"
    "default:my notes:my notes\n"
    "error connecting to /tmp/tmux-1000/x (No such file or directory)\n",
    "ssh -p 2222 user@box": "no server running on /tmp/tmux-1000/claude\n"
    "default:main:main\n",
    "ssh twin": "claude:dup:dup\ndefault:dup:dup\n",
    "ssh -t vm": "default:main:main\n",
}


def lookup(login: str) -> tuple[dict[str, list[str]], str]:
    """Return a fake host's sessions and raw output."""
    raw = HOSTS[login]
    return arr.parse_sessions(raw), raw


# The directories each fake host has: any but these are none there.
GONE = {("ssh vm", "/home/me/gone"), ("ssh vm", "/srv/on-the-next-host")}


def has_dir(login: str, path: str) -> bool:
    """Tell whether `path` is a directory on the fake host of `login`."""
    return (login, path) not in GONE


def save(tabs: list[Tab]) -> list[str]:
    """Return the lines saving `tabs` gives."""
    plans = [arr.plan(t, i, frozenset({LOCAL})) for i, t in enumerate(tabs, 1)]
    return arr.lines(plans, lookup, has_dir)


passed = failed = 0


def case(name: str) -> Callable[[Callable[[], None]], None]:
    """Run the decorated function as one case, logging PASS or FAIL."""

    def run(fn: Callable[[], None]) -> None:
        global passed, failed  # noqa: PLW0603
        try:
            fn()
        except Exception as e:  # noqa: BLE001 - a failed case is reported, then the rest run
            failed += 1
            log(f"FAIL {name}: {e!r}")
        else:
            passed += 1
            log(f"PASS {name}")

    return run


def error_of(fn: Callable[[], object]) -> str:
    """Return the ArrangementError message `fn` raises; fail if it raises none."""
    try:
        got = fn()
    except ArrangementError as e:
        return str(e)
    msg = f"no error; it returned {got!r}"
    raise AssertionError(msg)


def refused(tabs: list[Tab], want: str) -> None:
    """Assert that saving `tabs` raises an ArrangementError containing `want`."""
    error = error_of(lambda: save(tabs))
    assert want in error, f"error {error!r} lacks {want!r}"


@case("ssh tabs: tmux on either socket, a plain login in its directory, options kept")
def _() -> None:
    got = save(
        [
            Tab(1, "ssh", "ssh vm", "[vm/ai-agent]", "/home/me", "vm"),
            Tab(1, "ssh", "ssh vm", "fish:~/d/ai-agent", "/home/me/d/ai-agent", "vm"),
            Tab(1, "ssh", "ssh vm", "[vm/api/docs] ", "/home/me", "vm"),
            Tab(1, "ssh", "ssh -p 2222 user@box ./deploy.sh", "[main]", "/", "box"),
            Tab(1, "ssh", "ssh -p 2222 user@box", "fish:/", "/", "box"),
        ],
    )
    assert got == [
        "LC_TMUX_ATTACH=claude:ai-agent ssh -o SendEnv=LC_TMUX_ATTACH vm",
        "LC_LOGIN_DIR=%2Fhome%2Fme%2Fd%2Fai-agent ssh -o SendEnv=LC_LOGIN_DIR vm",
        "LC_TMUX_ATTACH=claude:api%2Fdocs ssh -o SendEnv=LC_TMUX_ATTACH vm",
        "LC_TMUX_ATTACH=default:main ssh -o SendEnv=LC_TMUX_ATTACH -p 2222 user@box",
        "LC_LOGIN_DIR=%2F ssh -o SendEnv=LC_LOGIN_DIR -p 2222 user@box",
    ], got


@case("an ssh tab whose far side reported nothing is saved as its login, with a note")
def _() -> None:
    # Its host is still the local one, and its path is ssh's local directory.
    tab = Tab(1, "ssh", "ssh vm", "fish:~/.dotfiles", "/Users/me/.dotfiles", LOCAL)
    assert save([tab]) == ["ssh vm"]
    p = arr.plan(tab, 3, frozenset({LOCAL}))
    assert "tab 3: its far side reported no host or directory" in p.note, p


@case("a remote directory with any character round-trips, with no / in the value")
def _() -> None:
    for path in ["/home/me/it's here", "/a+b/%41/c d/\u00fc", "/x;$y/`z`/~", "/a:b"]:
        tab = Tab(1, "ssh", "ssh -p 2222 vm", "fish", path, "vm")
        [line] = save([tab])
        value, _, rest = line.partition(" ")
        assert rest == "ssh -o SendEnv=LC_LOGIN_DIR -p 2222 vm", line
        # Tailscale SSH drops a value holding "/"; fish reads it as one word.
        assert "/" not in value, value
        assert re.fullmatch(r"LC_LOGIN_DIR=[A-Za-z0-9_.~:%-]+", value), value
        assert arr.dir_request(line) == path, (line, path)
        assert arr.attach_request(line) is None, line


@case("a remote directory iTerm2 reports as no absolute path is refused")
def _() -> None:
    refused([Tab(1, "ssh", "ssh vm", "fish", "", "vm")], "reports directory ''")


@case("a remote directory holding a newline is refused")
def _() -> None:
    refused([Tab(1, "ssh", "ssh vm", "fish", "/n\nl", "vm")], "holds a newline")


@case("a directory that is none on the login's host is refused: a nested ssh")
def _() -> None:
    # `ssh vm`, then `ssh next` from there: the tab reports next's directory.
    tab = Tab(1, "ssh", "ssh vm", "fish", "/srv/on-the-next-host", "next")
    refused([tab], "which is none on `ssh vm`: the tab ssh'd on from there")


@case("the directory check: one word for ssh, run by sh, y or n per directory")
def _() -> None:
    argv = arr.dirs_argv("ssh -p 2222 vm", unattended=False)
    assert argv[:4] == ["ssh", "-p", "2222", "vm"], argv
    # The remote word, run here by sh as a remote login shell would run it.
    paths = [str(REPO), "/no/such/dir", f"{REPO}/it's a $dir"]
    done = subprocess.run(  # noqa: S603 - the script under test
        ["/bin/sh", "-c", argv[4]],
        input="".join(f"{p}\n" for p in paths),
        capture_output=True,
        text=True,
        check=True,
    )
    assert done.stdout == "y\nn\nn\n", done
    assert arr.parse_dirs(done.stdout, paths) == {
        paths[0]: True,
        paths[1]: False,
        paths[2]: False,
    }


@case("a directory check answer of the wrong shape is refused, quoted")
def _() -> None:
    for text in ["y\n", "Welcome!\ny\nn\n", "y\nmaybe\n"]:
        error = error_of(lambda text=text: arr.parse_dirs(text, ["/a", "/b"]))
        assert "want y or n for each of 2 directories" in error, error
        assert text in error, error


@case("a tab restored by an earlier directory line saves one SendEnv, not two")
def _() -> None:
    restored = "ssh -o SendEnv=LC_LOGIN_DIR vm"
    got = save([Tab(1, "ssh", restored, "fish", "/srv", "vm")])
    assert got == ["LC_LOGIN_DIR=%2Fsrv ssh -o SendEnv=LC_LOGIN_DIR vm"], got


@case("a local tab reopens in its directory, quoted for fish")
def _() -> None:
    got = save([Tab(1, "nvim", "nvim .", "nvim", "/Users/me/it's here", LOCAL)])
    assert got == ["cd '/Users/me/it\\'s here'"], got


@case("a tab restored by an earlier attach line saves one attach, not two")
def _() -> None:
    # iTerm2's commandLine is ssh's argv: the variable is in its
    # environment, not on the line.
    restored = "ssh -o SendEnv=LC_TMUX_ATTACH vm"
    got = save([Tab(1, "ssh", restored, "[main]", "/", "vm")])
    assert got == ["LC_TMUX_ATTACH=default:main ssh -o SendEnv=LC_TMUX_ATTACH vm"], got


@case("attach_request reads back what attach_line wrote, and nothing else")
def _() -> None:
    for socket in arr.SOCKETS:
        line = arr.attach_line("ssh -p 2222 vm", socket, "api/docs")
        got = arr.attach_request(line)
        assert got == (socket, "api/docs"), (line, got)
    for line in ["ssh vm", "cd '/tmp'", "LC_TMUX_ATTACH=x:y ssh vm"]:
        assert arr.attach_request(line) is None, line
        assert arr.dir_request(line) is None, line
    assert arr.dir_request(arr.attach_line("ssh vm", "claude", "x")) is None


@case("a split tab is refused")
def _() -> None:
    refused([Tab(2, "fish", "fish", "fish", "/", LOCAL)], "2 panes")


@case("a session named with a space is refused as one to rename, not as on no socket")
def _() -> None:
    refused(
        [Tab(1, "ssh", "ssh vm", "[my notes]", "/", "vm")],
        "needing quotes; rename it",
    )


@case("a saved attach line on a socket the restore cannot land is refused at parse")
def _() -> None:
    for value, want in [
        ("work:main", "socket 'work'"),
        ("main", "socket 'main'"),  # no ":" at all
        ("claude:", "no session"),
    ]:
        line = f"LC_TMUX_ATTACH={value} ssh -o SendEnv=LC_TMUX_ATTACH vm"
        error = error_of(
            lambda line=line: arr.parse_file(f"window: x\nssh vm\n{line}\n"),
        )
        assert want in error, f"{error!r} lacks {want!r}"
        assert "line 3" in error, error


@case("TITLED is what ~/.tmux.conf's set-titles-string shows for each socket")
def _() -> None:
    conf = (REPO / "home/.tmux.conf").read_text()
    titles = re.findall(r"^set-option -g set-titles-string (.+)$", conf, re.MULTILINE)
    assert len(titles) == 1, titles
    for socket, shown in arr.TITLED.items():
        assert f"[{shown}]" in titles[0], (socket, shown, titles[0])


@case("a session on no socket is refused, with the host's output")
def _() -> None:
    refused([Tab(1, "ssh", "ssh vm", "[gone]", "/", "vm")], "on no socket")


@case("a claude session's bare name is not its title, so it matches nothing")
def _() -> None:
    refused([Tab(1, "ssh", "ssh vm", "[ai-agent]", "/", "vm")], "on no socket")


@case("a session on two sockets is refused")
def _() -> None:
    refused(
        [Tab(1, "ssh", "ssh twin", "[dup]", "/", "vm")],
        "sockets claude and default",
    )


@case("an ssh line Cmd-T would refuse is refused")
def _() -> None:
    refused(
        [Tab(1, "ssh", 'ssh -o "ProxyCommand x" vm', "fish", "/", "vm")],
        "cannot be replayed",
    )


@case("a local tab with no directory is refused")
def _() -> None:
    refused([Tab(1, "fish", "fish", "fish", "", LOCAL)], "no directory")


@case("a tmux session name that would need quoting is refused")
def _() -> None:
    error = error_of(lambda: arr.attach_line("ssh vm", "default", "my session"))
    assert "rename it" in error, error


@case("the file round-trips, comments and blank lines aside")
def _() -> None:
    windows = [
        Saved(
            "ai-agent \\(currentTab.currentSession.name)",
            ["LC_TMUX_ATTACH=default:x ssh -o SendEnv=LC_TMUX_ATTACH vm", "ssh vm"],
        ),
        Saved("", ["cd '/tmp'"]),
    ]
    text = arr.render("all", "2026-10-12T00:00:00Z", windows)
    assert arr.parse_file(text) == windows, text
    assert "\nwindow:\n" in text, "an empty template left a trailing space"


@case("hand edits that would restore the wrong thing are refused")
def _() -> None:
    for text, want in [
        ("# c\nssh vm\nwindow: x\nssh vm\n", "before any"),
        ("window: x\n\nwindow: y\nssh vm\n", "window 1 (line 1) has no tabs"),
        ("# only comments\n", 'no "window:" line'),
    ]:
        error = error_of(lambda text=text: arr.parse_file(text))
        assert want in error, f"{error!r} lacks {want!r}"


@case("the remote tmux ls: one word for ssh, quoted for a remote sh or fish")
def _() -> None:
    got = arr.list_sessions_argv("ssh -p 2222 vm", unattended=False)
    assert got == [
        "ssh",
        "-p",
        "2222",
        "vm",
        (
            "tmux -L claude ls -F 'claude:#{session_name}:#{host}/#{session_name}';"
            " tmux ls -F 'default:#{session_name}:#{session_name}'"
        ),
    ], got


class FakeSession:
    """A pane: the variables read_windows asks of it."""

    def __init__(self, sid: str) -> None:
        """Make pane `sid`, a local fish in /home/me."""
        self.session_id = sid
        self.vars = {
            "jobName": "fish",
            "commandLine": "-fish",
            "name": "fish",
            "path": "/home/me",
            "hostname": LOCAL,
        }

    async def async_get_variable(self, var: str) -> str:
        """Read one of its variables."""
        return self.vars[var]


class FakeTab:
    """A tab as iterm2 2.25 reports it: `sessions` leaves out minimized panes."""

    def __init__(self, shown: list[FakeSession], minimized: list[FakeSession]) -> None:
        """Make a tab of `shown` panes, and `minimized` ones behind a maximized one."""
        self.sessions = shown
        self.all_sessions = shown + minimized


class FakeWindow:
    """A window of tabs, with no title template."""

    def __init__(self, *tabs: FakeTab) -> None:
        """Make a window of `tabs`."""
        self.tabs = list(tabs)

    async def async_get_variable(self, var: str) -> str:
        """Read titleOverrideFormat, the only variable asked of a window here."""
        assert var == "titleOverrideFormat", var
        return ""


@case("a split tab with one pane maximized is still two panes, so refused")
def _() -> None:
    a, b = FakeSession("A"), FakeSession("B")
    app = types.SimpleNamespace(current_window=None)
    app.windows = [FakeWindow(FakeTab([a], [b]))]
    [(_, tabs)] = asyncio.run(arr.read_windows(app, None))
    assert tabs[0].panes == 2, tabs
    error = error_of(lambda: arr.plan(tabs[0], 1, frozenset({LOCAL})))
    assert "2 panes" in error, error


class Moving:
    """An iTerm2 session whose variables read `before`, then `then`."""

    def __init__(
        self,
        before: dict[str, str],
        then: dict[str, str],
        after: int,
    ) -> None:
        """Read from `before` for `after` reads (of any variable), then from `then`."""
        self.before, self.then, self.left = before, then, after

    async def async_get_variable(self, var: str) -> str:
        """Read one of its variables."""
        self.left -= 1
        return (self.before if self.left >= 0 else self.then)[var]


def titled(then: str, after: int) -> Moving:
    """Return a tab titled "fish" until it reads `then` (tmux attached)."""
    return Moving({"name": "fish"}, {"name": then}, after)


def in_dir(path: str, after: int, start: str = "/Users/me") -> Moving:
    """Return a tab local in `start` until it is in `path` on host "vm"."""
    return Moving(
        {"path": start, "hostname": LOCAL},
        {"path": path, "hostname": "vm"},
        after,
    )


def tmux_tab(label: str, name: str, s: Moving, socket: str = "claude") -> Landing:
    """Return the landing of a tmux tab."""
    return arr.tmux_landing(label, socket, name, s)


def dir_tab(label: str, path: str, s: Moving) -> Landing:
    """Return the landing of a directory tab, LOCAL being the local host."""
    return arr.dir_landing(label, path, frozenset({LOCAL}), s)


@case("restore waits for each tmux tab to show its session, each dir tab its path")
def _() -> None:
    tabs = [
        tmux_tab("window 1 tab 1", "ai-agent", titled("[vm/ai-agent]", 3)),
        tmux_tab("window 1 tab 2", "api/docs", titled("[vm/api/docs] ", 0)),
        dir_tab("window 1 tab 3", "/home/me/d", in_dir("/home/me/d", 4)),
        tmux_tab("window 1 tab 4", "main", titled("[main]", 2), socket="default"),
    ]
    asyncio.run(arr.wait_landed(tabs, timeout=5, poll=0.01))


@case("a tab still a shell at the timeout fails the restore, by name")
def _() -> None:
    tabs = [
        tmux_tab("window 1 tab 1", "ai-agent", titled("[vm/ai-agent]", 0)),
        tmux_tab("window 2 tab 3", "api/docs", titled("[vm/api/docs]", 10**6)),
        dir_tab("window 2 tab 4", "/home/me/d", in_dir("/home/me/d", 10**6)),
        dir_tab("window 2 tab 5", "/srv", in_dir("/srv", 0)),
    ]
    error = error_of(
        lambda: asyncio.run(arr.wait_landed(tabs, timeout=0.05, poll=0.01)),
    )
    assert "2 tabs did not land" in error, error
    assert "window 2 tab 3: want [<host>/api/docs], title reads 'fish'" in error, error
    want = (
        "window 2 tab 4: want directory '/home/me/d' off host 'Mac.local',"
        " path reads '/Users/me' on host 'Mac.local'"
    )
    assert want in error, error
    assert "window 1 tab 1" not in error, error
    assert "window 2 tab 5" not in error, error


@case("a claude tab has landed only on its own session, behind some host")
def _() -> None:
    for title, want in [
        ("[vm/api/docs]", True),
        ("[box/api/docs] ", True),
        ("[api/docs]", False),  # no host: the bare name is not a claude title
        ("[vm/api/docs2]", False),
        ("[vm/x/api/docs]", False),  # the host ends at the first "/"
        ("[vm-api/docs]", False),  # the form before 2026-10-22
        ("[main]", False),
    ]:
        s = titled(title, 0)
        tab = tmux_tab("t", "api/docs", s)
        got = asyncio.run(tab.reach(s))[0]
        assert got is want, (title, got)


@case("a tab still local in the very directory wanted has not landed (Mac to Mac)")
def _() -> None:
    tab = dir_tab("w1 t1", "/Users/me", in_dir("/Users/me", 10**6, start="/Users/me"))
    error = error_of(
        lambda: asyncio.run(arr.wait_landed([tab], timeout=0.05, poll=0.01)),
    )
    assert "path reads '/Users/me' on host 'Mac.local'" in error, error


@case("restore waits on the lines that ask for a session or a directory, only")
def _() -> None:
    s = in_dir("/x", 0)
    local = frozenset({LOCAL, "Mac"})
    attach = arr.attach_line("ssh vm", "claude", "api/docs")
    got = arr.landing_of("t", attach, s, local)
    assert got is not None, attach
    assert got.want == "[<host>/api/docs]", got
    got = arr.landing_of("t", arr.dir_line("ssh vm", "/a b"), s, local)
    assert got is not None
    assert got.want == "directory '/a b' off host 'Mac', 'Mac.local'", got
    for line in ["ssh vm", "cd '/tmp'"]:
        assert arr.landing_of("t", line, s, local) is None, line


@case("a dir tab on any of this Mac's names has not landed, though in the path")
def _() -> None:
    s = Moving({"path": "/Users/me", "hostname": "Mac"}, {}, 10**6)
    tab = arr.dir_landing("t", "/Users/me", frozenset({LOCAL, "Mac"}), s)
    assert asyncio.run(tab.reach(s))[0] is False


@case("a new tab's host is read once iTerm2 has set it, else the restore fails")
def _() -> None:
    s = Moving({"hostname": ""}, {"hostname": LOCAL}, 3)
    assert asyncio.run(arr.fresh_host("t", s, timeout=5, poll=0.001)) == LOCAL
    s = Moving({"hostname": ""}, {}, 10**6)
    error = error_of(
        lambda: asyncio.run(arr.fresh_host("w1 t2", s, timeout=0.01, poll=0.001)),
    )
    assert "w1 t2: iTerm2 reported hostname '' for the new tab" in error, error


class RestoredSession:
    """A new tab's pane: local until a line is typed, then where it leads.

    Each read and line goes to `events`, so a test sees their order.
    """

    def __init__(self, events: list[str]) -> None:
        """Start local in /Users/me, titled fish."""
        self.events = events
        self.vars = {"hostname": LOCAL, "path": "/Users/me", "name": "fish"}

    async def async_get_variable(self, var: str) -> str:
        """Read one of its variables."""
        self.events.append(f"read {var}")
        return self.vars[var]

    async def async_send_text(self, text: str) -> None:
        """Type `text`; the far side acts on its request at once."""
        line = text.removesuffix("\n")
        self.events.append(f"typed {line}")
        if request := arr.attach_request(line):
            self.vars["name"] = f"[vm/{request[1]}]"
        elif (where := arr.dir_request(line)) is not None:
            self.vars.update(path=where, hostname="vm")


class RestoredTab:
    """A tab of a RestoredWindow."""

    def __init__(self, events: list[str]) -> None:
        """Hold one new pane."""
        self.current_session = RestoredSession(events)


class RestoredWindow:
    """A window the restore makes, or one iTerm2 opened at its launch."""

    def __init__(self, app: "RestoredApp", wid: str) -> None:
        """Open window `wid` in `app`, with one tab."""
        self.app, self.window_id, self.template = app, wid, ""
        self.tabs = [RestoredTab(app.events)]
        self.current_tab = self.tabs[0]
        app.windows.append(self)

    async def async_create_tab(self) -> RestoredTab:
        """Open another tab."""
        self.tabs.append(RestoredTab(self.app.events))
        return self.tabs[-1]

    async def async_set_title(self, template: str) -> None:
        """Set its title template."""
        self.template = template

    async def async_get_variable(self, var: str) -> str:
        """Read titleOverrideFormat."""
        assert var == "titleOverrideFormat", var
        return self.template

    async def async_activate(self) -> None:
        """Bring it to the front."""
        self.app.events.append(f"activated {self.window_id}")

    async def async_close(self, *, force: bool) -> None:
        """Close it, unasked; `windows` drops it at the next refresh, as iTerm2's."""
        assert force
        self.app.closed.append(self.window_id)
        self.app.events.append(f"closed {self.window_id}")


class RestoredApp:
    """iTerm2 as a restore sees it: localhostName "Mac", windows by id."""

    def __init__(self) -> None:
        """Hold no window yet."""
        self.windows: list[RestoredWindow] = []
        self.closed: list[str] = []
        self.events: list[str] = []
        self.made = 0

    async def async_refresh(self) -> None:
        """Drop the windows closed since the last refresh."""
        self.windows = [w for w in self.windows if w.window_id not in self.closed]

    async def async_get_variable(self, var: str) -> str:
        """Read localhostName."""
        assert var == "localhostName", var
        return "Mac"

    async def create(self, _connection: object) -> RestoredWindow:
        """Open a window, as iterm2.Window.async_create does."""
        self.made += 1
        return RestoredWindow(self, f"made{self.made}")


SAVED = arr.parse_file(
    "window: a\n"
    + arr.dir_line("ssh vm", "/home/me/d")
    + "\n"
    + arr.attach_line("ssh vm", "claude", "x")
    + "\nwindow: b\ncd '/tmp'\n",
)


def restored(*, alone: bool) -> RestoredApp:
    """Return the app after restoring SAVED beside a window iTerm2 opened, "startup"."""
    app = RestoredApp()
    RestoredWindow(app, "startup")
    stub.Window.async_create = app.create
    try:
        asyncio.run(arr.restore(None, app, "t", SAVED, alone=alone))
    finally:
        del stub.Window.async_create
    return app


@case("restore reads a new dir tab's host before typing, so it needs no tab of its own")
def _() -> None:
    # Unset, so a restore that went back to reading them fails here.
    saved = {
        k: os.environ.pop(k) for k in ("TMUX", "ITERM_SESSION_ID") if k in os.environ
    }
    try:
        app = restored(alone=False)
    finally:
        os.environ.update(saved)
    typed = {e: i for i, e in enumerate(app.events) if e.startswith("typed ")}
    assert len(typed) == 3, app.events
    for line, i in typed.items():
        read = app.events[i - 1] == "read hostname"
        assert read is ("LC_LOGIN_DIR" in line), app.events[i - 1 : i + 1]
    assert [w.template for w in app.windows] == ["", "b", "a"], app.windows
    assert app.closed == [], app.closed


@case("replace: the restore closes every window it did not open, last")
def _() -> None:
    app = restored(alone=True)
    assert app.closed == ["startup"], app.closed
    assert app.events[-1] == "closed startup", app.events[-3:]
    assert app.events.index("activated made2") < app.events.index("closed startup")


@case("replace: a failed restore closes the startup window, not a half-made one")
def _() -> None:
    app = RestoredApp()
    RestoredWindow(app, "startup")
    stub.Window.async_create = app.create
    bad = [arr.Saved("a", ["cd '/tmp'"]), arr.Saved("b", ["cd '/x'"])]

    async def no_title(self: RestoredWindow, _template: str) -> None:
        """Leave the title unset, so its read-back fails the restore."""

    set_title = RestoredWindow.async_set_title
    RestoredWindow.async_set_title = no_title
    try:
        error = error_of(
            lambda: asyncio.run(arr.restore(None, app, "t", bad, alone=True)),
        )
    finally:
        RestoredWindow.async_set_title = set_title
        del stub.Window.async_create
    assert "window 2: title template reads back ''" in error, error
    assert app.closed == ["startup"], app.closed
    assert [w.window_id for w in app.windows] == ["startup", "made1"], app.windows


@case("replace refuses to run under iTerm2, whose quit would end it; tmux is fine")
def _() -> None:
    procs = {
        500: (400, "/Users/me/.nix-profile/bin/python3"),
        400: (300, "fish"),
        300: (200, "/Users/me/Library/Application Support/iTerm2/iTermServer-3.7.6"),
        200: (1, "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
        # a tmux pane: the server forked off to launchd
        60: (50, "fish"),
        50: (1, "tmux"),
        # Terminal.app
        70: (10, "-fish"),
        10: (1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
    }
    got = arr.iterm2_ancestor(500, procs.__getitem__)
    assert got == "300 " + procs[300][1], got
    assert arr.iterm2_ancestor(200, procs.__getitem__) == "200 " + procs[200][1]
    assert arr.iterm2_ancestor(60, procs.__getitem__) is None
    assert arr.iterm2_ancestor(70, procs.__getitem__) is None


@case("replace launches iTerm2 by open_clean.sh, so no tab inherits its env")
def _() -> None:
    # A plain `open` from a Claude Code Bash tool gave iTerm2, and every tab,
    # CLAUDE_CODE_CHILD_SESSION=1: each `claude` there then saved no transcript.
    # Resolved, as OPEN_CLEAN is: a worktree under /var is under /private/var.
    clean = (REPO / "scripts/macos/open_clean.sh").resolve()
    assert arr.launch_argv() == [str(clean), "-b", "com.googlecode.iterm2"]
    assert os.access(clean, os.X_OK), clean


@case("replace without open_clean.sh fails before anything closes, naming it")
def _() -> None:
    saved = arr.OPEN_CLEAN
    arr.OPEN_CLEAN = REPO / "no/such/open_clean.sh"
    try:
        error = error_of(arr.launch_argv)
    finally:
        arr.OPEN_CLEAN = saved
    assert "no/such/open_clean.sh is missing or not executable" in error, error


@case("an argument with a / is a path to an arrangement in DIR, named by its stem")
def _() -> None:
    assert arr.name_of("good") == "good"
    snap = arr.DIR / "auto-20261026_183220.txt"
    assert arr.name_of(str(snap)) == "auto-20261026_183220"
    tilde = "~/" + str((arr.DIR / "good.txt").relative_to(Path.home()))
    assert arr.name_of(tilde) == "good", tilde
    assert arr.name_of(str(arr.DIR / "x" / ".." / "good.txt")) == "good"


@case("a bare <name>.txt is a path too, one outside DIR refused, a symlink named")
def _() -> None:
    saved, cwd = arr.DIR, Path.cwd()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        arr.DIR = root / "arrangements"
        arr.DIR.mkdir()
        # Symlinked files are named as linked, not by their targets.
        (root / "elsewhere.txt").write_text("")
        (arr.DIR / "work.txt").symlink_to(root / "elsewhere.txt")
        (arr.DIR / "b.txt").write_text("")
        (arr.DIR / "a.txt").symlink_to(arr.DIR / "b.txt")
        try:
            assert arr.name_of(str(arr.DIR / "work.txt")) == "work"
            assert arr.name_of(str(arr.DIR / "a.txt")) == "a"
            # A shell's completion in DIR itself: no "/" at all.
            os.chdir(arr.DIR)
            assert arr.name_of("good.txt") == "good"
            # From elsewhere the same word is a file there, not DIR's.
            os.chdir(root)
            bad = ["good.txt", str(root / "good.txt"), str(arr.DIR / "good.bak")]
            for arg in [*bad, str(arr.DIR / "x/good.txt")]:
                error = error_of(lambda arg=arg: arr.name_of(arg))
                assert f"an arrangement is a <name>.txt in {arr.DIR}" in error, error
        finally:
            os.chdir(cwd)
            arr.DIR = saved


@case("ps names this process's parent, for replace's iTerm2 check")
def _() -> None:
    ppid, path = arr.ps_parent(os.getpid())
    assert ppid == os.getppid(), (ppid, os.getppid())
    assert path, path


class FakeApp:
    """An iTerm2 app holding one session, "ABC", on `host`."""

    def __init__(self, host: str) -> None:
        """Hold session ABC on `host`."""
        self.session = Moving({"hostname": host}, {}, 10**6)

    def get_session_by_id(self, sid: str) -> Moving | None:
        """Return session ABC, or None for any other id."""
        return self.session if sid == "ABC" else None


@case("the local host is the host of the iTerm2 session the script runs in")
def _() -> None:
    saved = {
        k: os.environ.pop(k) for k in ("TMUX", "ITERM_SESSION_ID") if k in os.environ
    }
    try:
        app = FakeApp(LOCAL)
        os.environ["ITERM_SESSION_ID"] = "w0t1p0:ABC"
        assert asyncio.run(arr.local_host(app)) == LOCAL
        os.environ["ITERM_SESSION_ID"] = "w0t1p0:XYZ"
        error = error_of(lambda: asyncio.run(arr.local_host(app)))
        assert "names no session" in error, error
        # Inside tmux the variable is the tab's that started the tmux session.
        os.environ["ITERM_SESSION_ID"] = "w0t1p0:ABC"
        os.environ["TMUX"] = "/private/tmp/tmux-1/default,1,0"
        error = error_of(lambda: asyncio.run(arr.local_host(app)))
        assert "run from inside tmux" in error, error
        del os.environ["TMUX"], os.environ["ITERM_SESSION_ID"]
        error = error_of(lambda: asyncio.run(arr.local_host(app)))
        assert "ITERM_SESSION_ID is unset" in error, error
    finally:
        for k in ("TMUX", "ITERM_SESSION_ID"):
            os.environ.pop(k, None)
        os.environ.update(saved)


class HostApp:
    """An iTerm2 app whose own localhostName is `own`."""

    def __init__(self, own: object) -> None:
        """Answer localhostName with `own`."""
        self.own = own

    async def async_get_variable(self, name: str) -> object:
        """Return localhostName; any other variable is a test bug."""
        assert name == "localhostName", name
        return self.own


@case("a snapshot's local hosts: those of the tabs not in ssh, and localhostName")
def _() -> None:
    windows = [
        (
            "w",
            [
                Tab(1, "fish", "fish", "fish", "/Users/me", LOCAL),
                Tab(1, "nvim", "nvim", "nvim", "/Users/me", "Mac"),
                Tab(1, "ssh", "ssh vm", "fish", "/home/me", "vm"),
            ],
        ),
    ]
    got = asyncio.run(arr.local_hosts(HostApp("Mac"), windows))
    assert got == {LOCAL, "Mac"}, got
    # Every tab in ssh: iTerm2's own name is all there is to go by.
    got = asyncio.run(arr.local_hosts(HostApp("Mac"), [("w", windows[0][1][2:])]))
    assert got == {"Mac"}, got
    error = error_of(lambda: asyncio.run(arr.local_hosts(HostApp(None), windows)))
    assert "localhostName None" in error, error


@case("an ssh tab whose far side said nothing is local by any of the local names")
def _() -> None:
    tab = Tab(1, "ssh", "ssh vm", "fish:~", "/Users/me", "Mac")
    p = arr.plan(tab, 1, frozenset({LOCAL, "Mac"}))
    assert (p.login, p.path) == ("ssh vm", ""), p
    assert "saved as the login" in p.note, p


@case("snapshots: named by their UTC time, all but the newest SNAPSHOT_KEEP dropped")
def _() -> None:
    now = datetime(2026, 10, 19, 14, 30, 0, tzinfo=UTC)
    assert arr.snapshot_name(now) == "auto-20261019_143000"
    # Three days old and all of them kept: a gap (iTerm2 quit over a
    # weekend) costs no snapshot from before it.
    keep = [
        f"auto-202610{16 + i // 144:02}_{i % 144 // 6:02}{i % 6 * 10:02}00"
        for i in range(arr.SNAPSHOT_KEEP + 2)
    ]
    names = ["all", *reversed(keep)]  # "all", a save by hand, is never dropped
    got = sorted(arr.stale_snapshots(names))
    assert got == keep[:2], got
    assert arr.stale_snapshots(keep[2:]) == []
    error = error_of(lambda: arr.stale_snapshots(["auto-mine"]))
    assert "'auto-mine' has the snapshot prefix" in error, error


@case("a missing arrangement's error lists the named ones and counts the snapshots")
def _() -> None:
    snaps = ["auto-20261026_151220", "auto-20261025_224220", "auto-20261026_141220"]
    got = arr.saved_summary(["good", snaps[0], "all", *snaps[1:]])
    assert got == "all, good; and 3 snapshots, newest auto-20261026_151220", got
    got = arr.saved_summary(snaps[:1])
    assert got == "1 snapshot, newest auto-20261026_151220", got
    assert arr.saved_summary(["good"]) == "good"
    assert arr.saved_summary([]) == "(none)"


@case("a snapshot's ssh asks for nothing and gives up on a host that is down")
def _() -> None:
    got = arr.list_sessions_argv("ssh -p 2222 vm", unattended=True)
    want = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-p", "2222", "vm"]
    assert got[:-1] == want, got
    got = arr.dirs_argv("ssh vm", unattended=True)
    assert got[:-1] == ["ssh", *arr.UNATTENDED_SSH, "vm"], got


log(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

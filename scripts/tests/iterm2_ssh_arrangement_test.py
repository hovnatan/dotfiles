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

# What `tmux ls` on each socket of each host prints.
HOSTS = {
    "ssh vm": "claude ai-agent\nclaude api/docs\ndefault main\n"
    "error connecting to /tmp/tmux-1000/x (No such file or directory)\n",
    "ssh -p 2222 user@box": "no server running on /tmp/tmux-1000/claude\n"
    "default main\n",
    "ssh twin": "claude dup\ndefault dup\n",
    "ssh -t vm": "default main\n",
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
    plans = [arr.plan(t, i, LOCAL) for i, t in enumerate(tabs, 1)]
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
            Tab(1, "ssh", "ssh vm", "[ai-agent]", "/home/me", "vm"),
            Tab(1, "ssh", "ssh vm", "fish:~/d/ai-agent", "/home/me/d/ai-agent", "vm"),
            Tab(1, "ssh", "ssh vm", "[api/docs] ", "/home/me", "vm"),
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
    p = arr.plan(tab, 3, LOCAL)
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
    argv = arr.dirs_argv("ssh -p 2222 vm")
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


@case("a session on no socket is refused, with the host's output")
def _() -> None:
    refused([Tab(1, "ssh", "ssh vm", "[gone]", "/", "vm")], "on no socket")


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
    got = arr.list_sessions_argv("ssh -p 2222 vm")
    assert got == [
        "ssh",
        "-p",
        "2222",
        "vm",
        (
            "tmux -L claude ls -F 'claude #{session_name}';"
            " tmux ls -F 'default #{session_name}'"
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
    error = error_of(lambda: arr.plan(tabs[0], 1, LOCAL))
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


def tmux_tab(label: str, name: str, s: Moving) -> Landing:
    """Return the landing of a tmux tab."""
    return arr.tmux_landing(label, name, s)


def dir_tab(label: str, path: str, s: Moving) -> Landing:
    """Return the landing of a directory tab, LOCAL being the local host."""
    return arr.dir_landing(label, path, LOCAL, s)


@case("restore waits for each tmux tab to show its session, each dir tab its path")
def _() -> None:
    tabs = [
        tmux_tab("window 1 tab 1", "ai-agent", titled("[ai-agent]", 3)),
        tmux_tab("window 1 tab 2", "api/docs", titled("[api/docs] ", 0)),
        dir_tab("window 1 tab 3", "/home/me/d", in_dir("/home/me/d", 4)),
    ]
    asyncio.run(arr.wait_landed(tabs, timeout=5, poll=0.01))


@case("a tab still a shell at the timeout fails the restore, by name")
def _() -> None:
    tabs = [
        tmux_tab("window 1 tab 1", "ai-agent", titled("[ai-agent]", 0)),
        tmux_tab("window 2 tab 3", "api/docs", titled("[api/docs]", 10**6)),
        dir_tab("window 2 tab 4", "/home/me/d", in_dir("/home/me/d", 10**6)),
        dir_tab("window 2 tab 5", "/srv", in_dir("/srv", 0)),
    ]
    error = error_of(
        lambda: asyncio.run(arr.wait_landed(tabs, timeout=0.05, poll=0.01)),
    )
    assert "2 tabs did not land" in error, error
    assert "window 2 tab 3: want [api/docs], title reads 'fish'" in error, error
    want = (
        "window 2 tab 4: want directory '/home/me/d' off host 'Mac.local',"
        " path reads '/Users/me' on host 'Mac.local'"
    )
    assert want in error, error
    assert "window 1 tab 1" not in error, error
    assert "window 2 tab 5" not in error, error


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
    attach = arr.attach_line("ssh vm", "claude", "api/docs")
    got = arr.landing_of("t", attach, s, None)
    assert got is not None, attach
    assert got.want == "[api/docs]", got
    got = arr.landing_of("t", arr.dir_line("ssh vm", "/a b"), s, LOCAL)
    assert got is not None
    assert got.want == "directory '/a b' off host 'Mac.local'", got
    for line in ["ssh vm", "cd '/tmp'"]:
        assert arr.landing_of("t", line, s, LOCAL) is None, line
    error = error_of(lambda: arr.landing_of("t", arr.dir_line("ssh vm", "/a"), s, None))
    assert "no local host was read" in error, error


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


log(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

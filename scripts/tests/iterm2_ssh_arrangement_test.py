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
vars(stub).update({n: type(n, (), {}) for n in ("App", "Connection", "Window")})
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


def save(tabs: list[Tab]) -> list[str]:
    """Return the lines saving `tabs` gives."""
    return arr.lines([arr.plan(t, i) for i, t in enumerate(tabs, 1)], lookup)


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


@case("ssh tabs: tmux on either socket, a plain login, options kept")
def _() -> None:
    got = save(
        [
            Tab(1, "ssh", "ssh vm", "[ai-agent]", "/Users/me"),
            Tab(1, "ssh", "ssh vm", "fish:~/d/ai-agent", "/Users/me"),
            Tab(1, "ssh", "ssh vm", "[api/docs] ", "/Users/me"),
            Tab(1, "ssh", "ssh -p 2222 user@box ./deploy.sh", "[main]", "/Users/me"),
        ],
    )
    assert got == [
        "ssh -t vm tmux -L claude attach -t =ai-agent",
        "ssh vm",
        "ssh -t vm tmux -L claude attach -t =api/docs",
        "ssh -t -p 2222 user@box tmux attach -t =main",
    ], got


@case("a local tab reopens in its directory, quoted for fish")
def _() -> None:
    got = save([Tab(1, "nvim", "nvim .", "nvim", "/Users/me/it's here")])
    assert got == ["cd '/Users/me/it\\'s here'"], got


@case("-t already given is not doubled")
def _() -> None:
    got = save([Tab(1, "ssh", "ssh -t vm", "[main]", "/")])
    assert got == ["ssh -t vm tmux attach -t =main"], got


@case("a split tab is refused")
def _() -> None:
    refused([Tab(2, "fish", "fish", "fish", "/")], "2 panes")


@case("a session on no socket is refused, with the host's output")
def _() -> None:
    refused([Tab(1, "ssh", "ssh vm", "[gone]", "/")], "on no socket")


@case("a session on two sockets is refused")
def _() -> None:
    refused([Tab(1, "ssh", "ssh twin", "[dup]", "/")], "sockets claude and default")


@case("an ssh line Cmd-T would refuse is refused")
def _() -> None:
    refused(
        [Tab(1, "ssh", 'ssh -o "ProxyCommand x" vm', "fish", "/")],
        "cannot be replayed",
    )


@case("a local tab with no directory is refused")
def _() -> None:
    refused([Tab(1, "fish", "fish", "fish", "")], "no directory")


@case("a tmux session name that would need quoting is refused")
def _() -> None:
    error = error_of(lambda: arr.attach_line("ssh vm", "default", "my session"))
    assert "rename it" in error, error


@case("the file round-trips, comments and blank lines aside")
def _() -> None:
    windows = [
        Saved(
            "ai-agent \\(currentTab.currentSession.name)",
            ["ssh -t vm tmux attach -t =x", "ssh vm"],
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
    """A pane: the four variables read_windows asks of it."""

    def __init__(self, sid: str) -> None:
        """Make pane `sid`, a local fish in /home/me."""
        self.session_id = sid
        self.vars = {
            "jobName": "fish",
            "commandLine": "-fish",
            "name": "fish",
            "path": "/home/me",
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
    error = error_of(lambda: arr.plan(tabs[0], 1))
    assert "2 panes" in error, error


log(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

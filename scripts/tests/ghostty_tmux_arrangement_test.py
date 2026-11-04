"""ghostty_tmux_arrangement.py: what Ghostty reports in, saved lines and plans out.

The pure part, with each host's `tmux ls` faked, so plain python3 runs it, as
CI has no Ghostty, tmux or ssh:

    osascript, tmux, ps text --> parse_*() --> line_of(fake lookup) --> lines
    saved windows --> render() --> parse_file() --> the same windows
    saved windows, what is open --> plan_restore() --> the tabs to open

    python3 ghostty_tmux_arrangement_test.py <repo> <event log>
"""

# A test script, not a package: asserts are its checks.
# Each check is named for what it shows, so its name is its docstring.
# ruff: noqa: S101, INP001, CPY001, D103

import importlib.util
import sys
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

REPO, LOG = Path(sys.argv[1]), Path(sys.argv[2])
log_file = LOG.open("a", buffering=1)


def log(msg: str) -> None:
    """Log a UTC-stamped line to the event log and stdout."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    log_file.write(line + "\n")
    print(line, flush=True)  # noqa: T201


spec = importlib.util.spec_from_file_location(
    "ghostty_tmux_arrangement",
    REPO / "scripts/lib/ghostty_tmux_arrangement.py",
)
assert spec
assert spec.loader
arr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arr)
shared = arr.tmux_arrangement
arr.LOG.append(LOG)  # the script's own log() lines land in this run's log
Client, Terminal, ArrangementError = arr.Client, arr.Terminal, arr.ArrangementError

ATTACH = "LC_TMUX_ATTACH=claude:api%2Fdocs ssh -o SendEnv=LC_TMUX_ATTACH vm"
SHELL_LOCAL = "tmux -L claude new-session -A -s 'notes' -c '/Users/me'"
SESSIONS = {"vm/api/docs": [("claude", "api/docs")], "main": [("default", "main")]}


def lookup(_login: str) -> tuple[dict[str, list[tuple[str, str]]], str]:
    """Answer as a host holding the sessions of SESSIONS."""
    return SESSIONS, "fake tmux ls"


def raises(text: str, fn: Callable[[], object]) -> None:
    """Assert `fn` raises an ArrangementError saying `text`."""
    try:
        fn()
    except ArrangementError as e:
        assert text in str(e), f"{text!r} is not in {e}"  # noqa: PT017
        return
    msg = f"no error saying {text!r}"
    raise AssertionError(msg)


def terminal(name: str) -> object:
    """Return a terminal titled `name`."""
    return Terminal("id-1", "/dev/ttys005", name)


failures = 0
passes = 0


def check(name: str, fn: Callable[[], None]) -> None:
    """Run one check, counting it; a failure does not hide the ones after it."""
    global failures, passes  # noqa: PLW0603
    try:
        fn()
    except AssertionError as e:
        failures += 1
        log(f"FAIL {name}: {e}")
    else:
        passes += 1
        log(f"PASS {name}")


def titles() -> None:
    assert arr.title_session("[vm/api/docs]") == "vm/api/docs"
    assert arr.title_session("(vm) [main]") == "main"
    assert arr.title_session("fish:~") is None
    assert arr.title_session("(vm) fish:~") is None


def local_lines_round_trip() -> None:
    client = Client("default", "it's/a", "/Users/me/it's here")
    line = arr.local_line(client)
    assert line == r"tmux new-session -A -s 'it\'s/a' -c '/Users/me/it\'s here'"
    assert arr.local_request(line) == client
    assert arr.local_request(SHELL_LOCAL) == Client("claude", "notes", "/Users/me")
    assert arr.local_request(ATTACH) is None


def a_local_line_on_another_socket_is_refused() -> None:
    raises(
        "not one of",
        lambda: arr.local_request("tmux -L probe new-session -A -s 'x' -c '/'"),
    )


def a_local_client_is_saved_whatever_its_title() -> None:
    client = Client("default", "main", "/Users/me")
    line = arr.line_of(1, terminal("fish:~"), client, "tmux", lookup)
    assert line == "tmux new-session -A -s 'main' -c '/Users/me'"


def an_ssh_tab_is_saved_from_its_title() -> None:
    line = arr.line_of(1, terminal("[vm/api/docs]"), None, "ssh vm", lookup)
    assert line == ATTACH


def an_ssh_title_with_the_host_prefix_still_reads() -> None:
    # The default socket outside iTerm2: tmux prefixes the host (.tmux.conf).
    line = arr.line_of(1, terminal("(vm) [main]"), None, "ssh vm", lookup)
    assert line == "LC_TMUX_ATTACH=default:main ssh -o SendEnv=LC_TMUX_ATTACH vm"


def what_is_no_tmux_is_skipped() -> None:
    assert arr.line_of(1, terminal("fish:~"), None, "-fish", lookup) is None
    assert arr.line_of(1, terminal("[looks/like]"), None, "nvim x", lookup) is None
    assert arr.line_of(1, terminal("fish:~"), None, "ssh vm", lookup) is None
    assert arr.line_of(1, terminal("fish:~"), None, "", lookup) is None


def a_session_on_no_socket_is_an_error() -> None:
    raises(
        "on no socket",
        lambda: arr.line_of(3, terminal("[vm/gone]"), None, "ssh vm", lookup),
    )


def an_ssh_line_that_cannot_be_replayed_is_an_error() -> None:
    raises(
        "cannot be replayed",
        lambda: arr.line_of(3, terminal("[vm/api/docs]"), None, "ssh", lookup),
    )


def foreground_picks_ssh() -> None:
    assert arr.foreground_of("Ss   -fish\nS+   ssh vm\n") == "ssh vm"
    assert arr.foreground_of("S+   tee x\nS+   /usr/bin/ssh vm\n") == "/usr/bin/ssh vm"
    assert arr.foreground_of("S+   -fish\n") == "-fish"
    assert arr.foreground_of("Ss   -fish\n") == ""
    assert arr.foreground_of("") == ""


def clients_parse() -> None:
    got = arr.parse_clients("default", "/dev/ttys1:a/b:/Users/me:odd\n")
    assert got == {"/dev/ttys1": Client("default", "a/b", "/Users/me:odd")}
    raises("printed", lambda: arr.parse_clients("default", "nonsense\n"))


def windows_parse() -> None:
    text = "window\x1fw1\nterminal\x1ft1\x1f/dev/ttys1\x1f[a]\nwindow\x1fw2\n"
    got = arr.parse_windows(text)
    assert [w.id for w in got] == ["w1", "w2"]
    assert got[0].terminals == [Terminal("t1", "/dev/ttys1", "[a]")]
    raises("no known shape", lambda: arr.parse_windows("nonsense\n"))
    raises("no known shape", lambda: arr.parse_windows("terminal\x1fa\x1fb\x1fc\n"))


def the_file_round_trips() -> None:
    windows = [[ATTACH, SHELL_LOCAL], [ATTACH]]
    text = arr.render("x", "2026-11-04T00:00:00Z", windows)
    assert arr.parse_file(text) == windows


def bad_files_are_refused() -> None:
    raises("before any", lambda: arr.parse_file(f"{ATTACH}\n"))
    raises("attaches no tmux", lambda: arr.parse_file("window:\ncd /tmp\n"))
    raises("has no tabs", lambda: arr.parse_file("window:\n"))
    raises('no "window:"', lambda: arr.parse_file("# only a comment\n"))
    raises(
        "line 2",
        lambda: arr.parse_file("window:\ntmux -L probe new-session -A -s 'x' -c '/'\n"),
    )


def yes(*_: object) -> bool:
    """Answer an alive or is_dir question with yes."""
    return True


def no(*_: object) -> bool:
    """Answer an alive or is_dir question with no."""
    return False


def what_is_open_is_skipped() -> None:
    plan = arr.plan_restore([[ATTACH], [SHELL_LOCAL]], [ATTACH], yes, yes)
    assert [[t.line for t in w] for w in plan] == [[SHELL_LOCAL]]


def a_local_session_is_the_same_in_another_directory() -> None:
    moved = "tmux -L claude new-session -A -s 'notes' -c '/tmp'"
    assert arr.plan_restore([[SHELL_LOCAL]], [moved], yes, yes) == []


def the_same_session_on_another_host_is_not_open() -> None:
    other = ATTACH.replace(" vm", " vm2")
    plan = arr.plan_restore([[ATTACH]], [other], yes, yes)
    assert len(plan) == 1


def a_gone_local_session_is_recreated_and_logged() -> None:
    before = LOG.read_text()
    plan = arr.plan_restore([[SHELL_LOCAL]], [], no, yes)
    assert [t.session for t in plan[0]] == ["notes"]
    assert "recreating empty, its programs are gone: notes" in (
        LOG.read_text().removeprefix(before)
    )


def a_gone_local_session_with_its_directory_gone_fails_first() -> None:
    raises(
        "directory /Users/me is too",
        lambda: arr.plan_restore([[ATTACH], [SHELL_LOCAL]], [], no, no),
    )


def landing() -> None:
    assert arr.landed("api/docs", "[vm/api/docs]")
    assert arr.landed("main", "(vm) [main]")
    assert arr.landed("main", "[main]")
    assert not arr.landed("docs", "fish:~")
    assert not arr.landed("docs", "[vm/api]")
    assert not arr.landed("api", "[vm/api-old]")


def snapshots_prune_in_the_given_folder() -> None:
    start = datetime(2026, 11, 1, tzinfo=UTC)
    names = [
        shared.snapshot_name(start + timedelta(minutes=i))
        for i in range(shared.SNAPSHOT_KEEP + 2)
    ]
    assert shared.stale_snapshots(names, Path("/x")) == names[1::-1]
    raises("/x/auto-x.txt", lambda: shared.stale_snapshots(["auto-x"], Path("/x")))


for name, fn in [(k, v) for k, v in list(globals().items()) if callable(v)]:
    if getattr(fn, "__module__", "") == "__main__" and name not in (
        "log",
        "lookup",
        "raises",
        "terminal",
        "check",
        "yes",
        "no",
    ):
        check(name.replace("_", " "), fn)

log(f"{passes} passed, {failures} failed")
sys.exit(1 if failures else 0)

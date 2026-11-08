"""ghostty_tmux_arrangement.py: what Ghostty reports in, saved lines and plans out.

The pure part, with each host's `tmux ls` faked, so plain python3 runs it, as
CI has no Ghostty, tmux or ssh:

    osascript, tmux, ps text --> parse_*() --> line_of(fake lookup) --> lines
    saved windows --> render() --> parse_file() --> the same windows
    saved windows, what is open --> plan_restore() --> the tabs to open
    replace(), Ghostty and tmux faked --> the order of what it opened and closed

    python3 ghostty_tmux_arrangement_test.py <repo> <event log>
"""

# A test script, not a package: asserts are its checks.
# Each check is named for what it shows, so its name is its docstring.
# ruff: noqa: S101, INP001, CPY001, D103

import importlib.util
import socket
import sys
import tempfile
from collections.abc import Callable, Generator
from contextlib import contextmanager
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
SESSIONS = {"api/docs": ["claude"], "main": ["default"]}


def lookup(_login: str) -> tuple[dict[str, list[str]], str]:
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
    assert arr.title_session("[api/docs]") == "api/docs"
    assert arr.title_session("(vm) [main]") == "main"
    assert arr.title_session("fish:~") is None
    assert arr.title_session("(vm) fish:~") is None


def local_lines_round_trip() -> None:
    client = Client("default", "it's/a", "/Users/me/it's here")  # no -L
    line = arr.local_line(client)
    assert line == r"tmux new-session -A -s 'it\'s/a' -c '/Users/me/it\'s here'"
    assert arr.local_request(line) == client
    assert arr.local_request(SHELL_LOCAL) == Client("claude", "notes", "/Users/me")
    assert arr.local_request(ATTACH) is None


def a_local_line_on_any_socket_reads_back() -> None:
    client = Client("work.2", "x", "/")
    assert arr.local_request(arr.local_line(client)) == client


def a_local_line_on_a_socket_no_plain_name_is_refused() -> None:
    raises(
        "not a plain name",
        lambda: arr.local_request("tmux -L -x new-session -A -s 'x' -c '/'"),
    )


def local_sockets_are_found_by_looking() -> None:
    # In /tmp: a unix socket's path may not run past 104 bytes on a Mac.
    with tempfile.TemporaryDirectory(dir="/tmp") as held:
        directory = Path(held)
        assert shared.local_sockets(directory / "none") == []
        for name in ("work", "default"):
            bound = socket.socket(socket.AF_UNIX)
            bound.bind(str(directory / name))
            bound.close()  # the file stays, as one a dead server left
        (directory / "a-file").touch()
        assert shared.local_sockets(directory) == ["default", "work"]
        bound = socket.socket(socket.AF_UNIX)
        bound.bind(str(directory / "-odd"))
        bound.close()
        raises("not a plain name", lambda: shared.local_sockets(directory))


def a_local_client_is_saved_whatever_its_title() -> None:
    client = Client("default", "main", "/Users/me")
    line = arr.line_of(1, terminal("fish:~"), client, "tmux", lookup)
    assert line == "tmux new-session -A -s 'main' -c '/Users/me'"


def an_ssh_tab_is_saved_from_its_title() -> None:
    line = arr.line_of(1, terminal("[api/docs]"), None, "ssh vm", lookup)
    assert line == ATTACH


def an_ssh_title_with_the_host_prefix_still_reads() -> None:
    # Outside iTerm2 tmux prefixes the host (tmux.conf).
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
        lambda: arr.line_of(3, terminal("[gone]"), None, "ssh vm", lookup),
    )


def an_ssh_line_that_cannot_be_replayed_is_an_error() -> None:
    raises(
        "cannot be replayed",
        lambda: arr.line_of(3, terminal("[api/docs]"), None, "ssh", lookup),
    )


def foreground_picks_ssh() -> None:
    assert arr.foreground_of("Ss   -fish\nS+   ssh vm\n") == "ssh vm"
    assert arr.foreground_of("S+   tee x\nS+   /usr/bin/ssh vm\n") == "/usr/bin/ssh vm"
    assert arr.foreground_of("S+   -fish\n") == "-fish"
    assert arr.foreground_of("Ss   -fish\n") == ""
    assert arr.foreground_of("") == ""


def clients_parse() -> None:
    got = arr.tmux_arrangement.parse_clients(
        "default",
        "/dev/ttys1:a/b:/Users/me:odd\n",
    )
    assert got == {"/dev/ttys1": Client("default", "a/b", "/Users/me:odd")}
    raises(
        "printed",
        lambda: arr.tmux_arrangement.parse_clients("default", "nonsense\n"),
    )


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
        lambda: arr.parse_file("window:\ntmux -L -x new-session -A -s 'x' -c '/'\n"),
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
    assert arr.landed("api/docs", "[api/docs]")
    assert arr.landed("main", "(vm) [main]")
    assert arr.landed("main", "[main]")
    assert not arr.landed("docs", "fish:~")
    assert not arr.landed("docs", "[api/docs]")
    assert not arr.landed("api", "[api-old]")


def snapshots_prune_in_the_given_folder() -> None:
    start = datetime(2026, 11, 1, tzinfo=UTC)
    names = [
        shared.snapshot_name(start + timedelta(minutes=i))
        for i in range(shared.SNAPSHOT_KEEP + 2)
    ]
    assert shared.stale_snapshots(names, Path("/x")) == names[1::-1]
    raises("/x/auto-x.txt", lambda: shared.stale_snapshots(["auto-x"], Path("/x")))


def test_a_window_listed_twice_fails_the_read() -> None:
    raises(
        "listed a window twice",
        lambda: arr.parse_windows("window\x1fa\nwindow\x1fa\n"),
    )


def test_the_window_read_fetches_each_list_whole() -> None:
    # Live Ghostty is not here to reorder: the script's text is what can be held.
    for part in ["windows", "tabs of w", "terminals of t"]:
        assert f"in (get {part})" in arr.READ_WINDOWS, part


def test_idle_is_a_bare_shell_or_nothing() -> None:
    for command in ["", "-fish", "fish", "/bin/zsh", "-zsh", "bash"]:
        assert arr.idle(command), command
    for command in ["vim", "fish build.fish", "sleep 100", "ssh vm"]:
        assert not arr.idle(command), command


def test_busy_terminals_names_what_a_close_would_kill() -> None:
    commands = {
        "/dev/t1": "ignored: a local tmux client",
        "/dev/t2": "ssh vm",  # a tmux title: its session stays on the far side
        "/dev/t3": "ssh vm",  # no tmux title: a login is lost
        "/dev/t4": "-fish",
        "/dev/t5": "vim notes",
    }
    window = arr.Window(
        "w",
        [
            Terminal("1", "/dev/t1", "[main]"),
            Terminal("2", "/dev/t2", "[vm/api]"),
            Terminal("3", "/dev/t3", "vm: ~"),
            Terminal("4", "/dev/t4", "fish"),
            Terminal("5", "/dev/t5", "notes"),
        ],
    )
    clients = {"/dev/t1": Client("default", "main", "/")}
    got = arr.busy_terminals([window], clients, commands.__getitem__)
    assert got == ["'vm: ~' (ssh vm)", "'notes' (vim notes)"], got


def test_ancestor_finds_ghostty_above_login_not_above_a_tmux_pane() -> None:
    app = "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    procs = {
        30: (20, "-fish"),
        20: (10, "/usr/bin/login"),
        10: (1, app),
        60: (50, "fish"),
        50: (1, "tmux"),
    }

    def is_ghostty(exe: str) -> bool:
        return exe == "ghostty"

    assert shared.ancestor(30, procs.__getitem__, is_ghostty) == f"10 {app}"
    assert shared.ancestor(60, procs.__getitem__, is_ghostty) is None


@contextmanager
def patched(**fakes: object) -> Generator[None]:
    """Put `fakes` in the script's namespace for the block, then take them back."""
    saved = {k: getattr(arr, k) for k in fakes}
    for k, v in fakes.items():
        setattr(arr, k, v)
    try:
        yield
    finally:
        for k, v in saved.items():
            setattr(arr, k, v)


def replacing(  # noqa: PLR0913 - what a run differs by, each with its usual value
    *,
    running: bool = True,
    under: str | None = None,
    land: Callable[[dict[str, str]], None] = lambda _waiting: None,
    command: str = "-fish",
    lines: tuple[str, ...] = (SHELL_LOCAL,),
    is_alive: bool = True,
) -> tuple[list[str], str]:
    """Run replace() on fakes: return what it did, in order, and its error."""
    done: list[str] = []
    old = [arr.Window("old1", [Terminal("t1", "/dev/t1", "x")]), arr.Window("old2", [])]

    def osascript(script: str, *args: str) -> str:
        verb = {arr.CLOSE_WINDOW: "close", arr.ACTIVATE: "activate"}[script]
        done.append(f"{verb} {args[0]}")
        return ""

    def open_tabs(plan: list[list[object]]) -> tuple[list[str], dict[str, str]]:
        done.append(f"open {len(plan)}")
        return ["new1"], {"t9": "notes"}

    def launch() -> list[object]:
        done.append("launch")
        return old[:1]

    with patched(
        load=lambda _name: [list(lines)],
        ancestor=lambda *_args: under,
        alive=lambda _client: is_alive,
        ghostty_running=lambda: running,
        launch=launch,
        read_windows=lambda: old,
        local_clients=dict,
        foreground=lambda _tty: command,
        open_tabs=open_tabs,
        wait_landed=land,
        osascript=osascript,
    ):
        try:
            arr.replace("x")
        except ArrangementError as e:
            return done, str(e)
    return done, ""


def test_replace_closes_the_old_windows_only_after_the_new_ones_land() -> None:
    done, error = replacing()
    assert not error, error
    assert done == ["open 1", "close old1", "close old2", "activate new1"], done


def test_replace_that_does_not_land_closes_nothing() -> None:
    def never(_waiting: dict[str, str]) -> None:
        msg = "1 tabs never showed their session: notes"
        raise ArrangementError(msg)

    done, error = replacing(land=never)
    assert done == ["open 1"], done
    assert "never showed their session: notes" in error, error
    assert "the 2 windows open before are left" in error, error


def test_replace_refuses_a_busy_terminal_before_opening_anything() -> None:
    done, error = replacing(command="vim notes")
    assert not done, done
    assert "would kill 'x' (vim notes)" in error, error


def test_replace_refuses_to_run_under_ghostty() -> None:
    done, error = replacing(under="10 /Applications/Ghostty.app/.../ghostty")
    assert not done, done
    assert "runs under Ghostty" in error, error


def test_replace_launches_ghostty_and_closes_its_startup_window() -> None:
    # A login not yet a shell would read as busy: a launch's window is not asked.
    done, error = replacing(running=False, command="login -flp me")
    assert not error, error
    assert done == ["launch", "open 1", "close old1", "activate new1"], done


def test_replace_with_a_dead_directory_fails_before_any_launch() -> None:
    gone = "tmux new-session -A -s 'x' -c '/no/such/dir'"
    done, error = replacing(running=False, lines=(gone,), is_alive=False)
    assert not done, done
    assert "local tmux session 'x' is gone" in error, error


def restoring(
    *,
    running: bool = True,
    land: Callable[[dict[str, str]], None] = lambda _waiting: None,
    lines: tuple[str, ...] = (SHELL_LOCAL,),
    is_alive: bool = True,
) -> tuple[list[str], str]:
    """Run restore() on fakes: return what it did, in order, and its error."""
    done: list[str] = []
    started = {"yes": running}
    startup = [arr.Window("start1", [Terminal("t0", "/dev/t0", "fish")])]

    def osascript(script: str, *args: str) -> str:
        verb = {arr.CLOSE_WINDOW: "close", arr.ACTIVATE: "activate"}[script]
        done.append(f"{verb} {args[0]}")
        return ""

    def read_windows() -> list[object]:
        # Asking a Ghostty that does not run would launch it, unclean.
        assert started["yes"], "read_windows() before Ghostty runs"
        return []

    def launch() -> list[object]:
        done.append("launch")
        started["yes"] = True
        return startup

    def open_tabs(plan: list[list[object]]) -> tuple[list[str], dict[str, str]]:
        done.append(f"open {len(plan)}")
        return ["new1"], {"t9": "notes"}

    with patched(
        load=lambda _name: [list(lines)],
        alive=lambda _client: is_alive,
        ghostty_running=lambda: started["yes"],
        launch=launch,
        read_windows=read_windows,
        local_clients=dict,
        remote_lookup=lambda **_kw: lookup,
        open_tabs=open_tabs,
        wait_landed=land,
        osascript=osascript,
    ):
        try:
            arr.restore("x")
        except ArrangementError as e:
            return done, str(e)
    return done, ""


def test_restore_beside_a_running_ghostty_launches_and_closes_nothing() -> None:
    done, error = restoring()
    assert not error, error
    assert done == ["open 1", "activate new1"], done


def test_restore_launches_ghostty_itself_and_closes_its_startup_window() -> None:
    # Launched by launch() (open_clean.sh), never left to the caller's `open`.
    done, error = restoring(running=False)
    assert not error, error
    assert done == ["launch", "open 1", "close start1", "activate new1"], done


def test_restore_that_does_not_land_keeps_the_startup_window() -> None:
    def never(_waiting: dict[str, str]) -> None:
        msg = "1 tabs never showed their session: notes"
        raise ArrangementError(msg)

    done, error = restoring(running=False, land=never)
    assert done == ["launch", "open 1"], done
    assert "never showed their session" in error, error


def test_restore_with_a_dead_directory_fails_before_any_launch() -> None:
    gone = "tmux new-session -A -s 'x' -c '/no/such/dir'"
    done, error = restoring(running=False, lines=(gone,), is_alive=False)
    assert not done, done
    assert "local tmux session 'x' is gone" in error, error


def test_save_without_ghostty_asks_for_no_launch() -> None:
    # "start it first" once got Ghostty a bare `open`, with an agent's env.
    want = "Ghostty is not running, so it has no windows to save"
    with patched(ghostty_running=lambda: False):
        raises(want, arr.require_ghostty)


for name, fn in [(k, v) for k, v in list(globals().items()) if callable(v)]:
    if getattr(fn, "__module__", "") == "__main__" and name not in (
        "log",
        "lookup",
        "raises",
        "terminal",
        "check",
        "yes",
        "no",
        "patched",
        "replacing",
        "restoring",
    ):
        check(name.replace("_", " "), fn)

log(f"{passes} passed, {failures} failed")
sys.exit(1 if failures else 0)

"""tmux_server_arrangement.py: its file, restore's pick, the run, restore, replace.

pure      render() / parse(): a round trip, a directory's spaces kept; each
          malformed line refused, naming it
          default_restore(): the newest snapshot before the server started
end to    the run as tmux.conf starts it (its own line, cut out, a snapshot
end       every second, not ten minutes), on throwaway servers in a socket
          folder of their own (TMUX_TMPDIR) and a throwaway HOME:

  server 1: api (a; f, its       -> a snapshot, by the run: api [a, f, "b  c "],
    window 1 split, f active;       solo [e]; no tmux-history; then none
    "b  c "), solo (e),             written while nothing changes
    tmux-history
  tmux.conf sourced again        -> the second run exits; still one
  save keep, list                -> keep.txt; list names both
  kill-server                    -> the run stops
  server 2: main, its own run    -> restore (no name) takes server 1's last
    snapshotting it                 snapshot, not server 2's: api and solo
                                    back, a window per saved one, each in
                                    its directory; main kept. Again: nothing
                                    changes, each logged as already open
  replace only-api (by hand),    -> refused, naming main:0.0 sleep;
    main running sleep              nothing closed
  the same, main running `bash   -> refused, naming both by their whole
    <script>`, job started as       command line (tmux names them "bash"
    `sh <script>`                   and "sh")
  the same from inside solo      -> refused: it would close its own session
  replace only-api, main idle    -> main and solo closed, api kept,
                                    tmux-history kept
  restore of a session whose     -> exit 1, the directory named, nothing
    directory is gone               created

python3 tmux_server_arrangement_test.py <repo> <event log>
"""

# A test script, not a package: asserts are its checks.
# Each check is named for what it shows, so its name is its docstring.
# ruff: noqa: S101, INP001, CPY001, D103, S603

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

REPO, LOG = Path(sys.argv[1]), Path(sys.argv[2])
SCRIPT = REPO / "scripts/tmux_server_arrangement.py"
spec = importlib.util.spec_from_file_location("tmux_server_arrangement", SCRIPT)
assert spec
assert spec.loader
ta = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ta)
log = ta.EventLog(LOG.open("a", buffering=1, encoding="utf-8"), sys.stdout).note


def raised(fn: Callable[[], object]) -> str:
    """Return the ArrangementError `fn` raised; fail if none."""
    try:
        fn()
    except ta.ArrangementError as e:
        return str(e)
    msg = "no ArrangementError"
    raise AssertionError(msg)


# --- the pure part -------------------------------------------------------------


def test_render_and_parse_round_trip_keeping_a_directorys_spaces() -> None:
    arr = {"api work": ["/x/a", "/x/b  c "], "solo": ["/y"]}
    text = ta.render(arr, "a header")
    assert text.splitlines()[:3] == ["# a header", "session api work", "  window /x/a"]
    assert ta.parse(text, "f") == arr


def test_parse_refuses_each_malformed_line_naming_it() -> None:
    cases = {
        "window /x\n": "f:1: a window before any session",
        "session a\n  window x\n": "f:2: '  window x' is neither",
        "session a\n  pane /x\n": "f:2: '  pane /x' is neither",
        "session a\n  window /x\nsession a\n": "f:3: session 'a' a second time",
        "session a\nsession b\n  window /x\n": "f: session(s) with no window: a",
    }
    for text, want in cases.items():
        msg = raised(lambda text=text: ta.parse(text, "f"))
        assert msg.startswith(want), (text, msg)


def test_default_restore_takes_the_newest_snapshot_before_the_server_started() -> None:
    saved = [
        "all",
        "auto-20261110_095000",
        "auto-20261110_100000",
        "auto-20261110_101500",
    ]
    started = datetime(2026, 11, 10, 10, 5, tzinfo=UTC)
    assert ta.default_restore(saved, started) == "auto-20261110_100000"
    assert ta.default_restore(saved, None) == "auto-20261110_101500"
    early = datetime(2026, 11, 10, 9, 0, tzinfo=UTC)
    assert "no snapshot before this server started" in raised(
        lambda: ta.default_restore(saved, early),
    )
    assert "no YYYYMMDD_HHMMSS" in raised(lambda: ta.default_restore(["auto-x"], None))


# --- end to end ------------------------------------------------------------------

WORK = Path(tempfile.mkdtemp(prefix="tmux_server_arrangement_test."))
HOME = WORK / "home"
D = WORK / "dirs"
# Unix socket paths are capped near 104 bytes: the socket folder is short.
# Resolved, as tmux resolves #{socket_path}: on macOS /tmp is a link.
SOCKETS = Path(tempfile.mkdtemp(prefix="tsatest.", dir="/tmp")).resolve()
SOCKET = SOCKETS / f"tmux-{os.getuid()}" / "default"
STATE = HOME / ".local/state/tmux_server_arrangements/default"
LOGS = HOME / ".dotfiles/.logs"
CONF = WORK / "tmux.conf"
TMUX = shutil.which("tmux") or "tmux"
# The servers' environment, which their run-shell jobs inherit: the
# throwaway HOME, where the snapshots and logs land, and tmux's socket folder.
ENV = {
    **{
        k: v
        for k, v in os.environ.items()
        if k not in {"TMUX", "TMUX_PANE", "TMUX_TMPDIR"}
    },
    "HOME": str(HOME),
    "TMUX_TMPDIR": str(SOCKETS),
}


def setup() -> None:
    """Make the throwaway HOME, the directories, and the config.

    tmux.conf's own run line, a snapshot every second; panes run sh, an
    idle shell to replace.
    """
    (HOME / ".dotfiles").mkdir(parents=True)
    (HOME / ".dotfiles/scripts").symlink_to(REPO / "scripts")
    for d in ("a", "b  c ", "e", "f", "main"):
        (D / d).mkdir(parents=True)
    conf = (REPO / "home/.config/tmux/tmux.conf").read_text().splitlines()
    (line,) = [
        x
        for x in conf
        if "tmux_server_arrangement.py run" in x and not x.startswith("#")
    ]
    assert " run -S " in line, line
    fast = line.replace(" run -S ", " run --every 1 -S ")
    CONF.write_text(f"set -g default-shell /bin/sh\n{fast}\n")


def tmux(
    *args: str,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run tmux on the test server; return what it did."""
    return subprocess.run(
        [TMUX, "-L", "default", *args],
        env=env or ENV,
        capture_output=True,
        text=True,
        check=False,
    )


def t(*args: str) -> str:
    """Run tmux on the test server; return its stdout, failing on an error."""
    r = tmux(*args)
    assert r.returncode == 0, f"tmux {args}: {r.stderr}"
    return r.stdout


def cli(
    *args: str,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run the script as a person would, on the test server."""
    return subprocess.run(
        [sys.executable, str(SCRIPT), args[0], "-L", "default", *args[1:]],
        env=env or ENV,
        capture_output=True,
        text=True,
        check=False,
    )


def until(what: str, fn: Callable[[], bool], timeout: float = 5.0) -> None:
    """Wait for `fn` to hold; fail naming `what` after `timeout` s."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if fn():
            return
        time.sleep(0.1)
    msg = f"{what}: not after {timeout:g} s"
    raise AssertionError(msg)


def snapshots() -> list[str]:
    return sorted(p.stem for p in STATE.glob("auto-*.txt"))


def runs() -> list[str]:
    """Return the pids of the snapshot runs on the test socket."""
    r = subprocess.run(
        [
            shutil.which("pgrep") or "pgrep",
            "-f",
            f"tmux_server_arrangement.py run .*{re.escape(str(SOCKET))}",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return r.stdout.split()


def logged() -> str:
    return "".join(
        p.read_text()
        for p in sorted(LOGS.glob("*_tmux_server_arrangement*/events.log"))
    )


def windows() -> dict[str, list[str]]:
    """Return each session's windows' directories, as tmux lists them."""
    out: dict[str, list[str]] = {}
    for line in t(
        "list-windows",
        "-a",
        "-F",
        "#{session_name}\t#{pane_current_path}",
    ).splitlines():
        session, d = line.split("\t")
        out.setdefault(session, []).append(d)
    return out


def pane_command(target: str) -> str:
    """Return the program tmux names the pane's foreground after."""
    return t("display", "-p", "-t", target, "#{pane_current_command}").strip()


def run_end_to_end() -> None:  # noqa: PLR0915 - one story, step by step
    setup()
    a, f, bc, e, main = (str(D / x) for x in ("a", "f", "b  c ", "e", "main"))

    # server 1, and its run's snapshots
    t("-f", str(CONF), "new-session", "-d", "-s", "api", "-c", a)
    t("new-window", "-d", "-t", "=api:", "-c", a)
    t("split-window", "-t", "=api:1", "-c", f)  # the split is active: f
    t("new-window", "-d", "-t", "=api:", "-c", bc)
    t("new-session", "-d", "-s", "solo", "-c", e)
    t("new-session", "-d", "-s", "tmux-history", "-c", a)
    until("a snapshot", lambda: bool(snapshots()))
    first = snapshots()[0]
    got = ta.parse((STATE / f"{first}.txt").read_text(), first)
    assert got == {"api": [a, f, bc], "solo": [e]}, got
    passed("the run snapshots each session's windows and directories, no tmux-history")
    time.sleep(2.5)
    assert snapshots() == [first], snapshots()
    assert f"snapshot: unchanged since {first}; none written" in logged(), logged()
    passed("an unchanged server writes no snapshot")

    t("source-file", str(CONF))
    until(
        "the second run's exit",
        lambda: "another run holds this server's lock" in logged(),
    )
    assert len(runs()) == 1, runs()
    passed("tmux.conf sourced again: the second run exits, one left")

    r = cli("save", "keep")
    assert r.returncode == 0, r.stdout + r.stderr
    assert ta.parse((STATE / "keep.txt").read_text(), "keep") == got
    r = cli("list")
    assert re.search(rf"^{first}  2 sessions, 4 windows$", r.stdout, re.MULTILINE), (
        r.stdout
    )
    assert re.search(r"^keep  2 sessions, 4 windows$", r.stdout, re.MULTILINE), r.stdout
    passed("save keep writes keep.txt; list names it and the snapshot")

    t("kill-server")
    until("the run's exit", lambda: not runs())
    assert re.search(r"stopped: (SIGTERM|the server is gone)", logged()), logged()
    passed("the run stops with its server")

    # server 2: restore server 1's last snapshot, beside main
    last = snapshots()[-1]
    t("-f", str(CONF), "new-session", "-d", "-s", "main", "-c", main)
    until("server 2's own snapshot", lambda: snapshots()[-1] != last)
    r = cli("restore")
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"restore {last}: 2 to create, 0 already open" in r.stdout, r.stdout
    assert windows() == {"api": [a, f, bc], "main": [main], "solo": [e]}, windows()
    passed("restore takes server 1's last snapshot: each window back in its directory")
    r = cli("restore")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "left api as it is: already open" in r.stdout, r.stdout
    assert windows() == {"api": [a, f, bc], "main": [main], "solo": [e]}, windows()
    passed("restore again: nothing changes, each session logged as already open")

    # replace: refused while main is busy, or from inside solo; then done
    t("new-session", "-d", "-s", "tmux-history", "-c", a)
    (STATE / "only-api.txt").write_text(f"session api\n  window {a}\n")
    t("send-keys", "-t", "=main:0", "exec sleep 300", "Enter")
    until(
        "main running sleep",
        lambda: (
            t("display", "-p", "-t", "=main:0", "#{pane_current_command}").strip()
            == "sleep"
        ),
    )
    r = cli("replace", "only-api")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "main:0.0 sleep" in r.stdout, r.stdout
    assert sorted(windows()) == ["api", "main", "solo", "tmux-history"], windows()
    passed("replace refuses while a session to close runs a program, naming its pane")
    t("respawn-pane", "-k", "-t", "=main:0", "-c", main)

    # A script is busy though tmux names its pane after the shell running it
    # ("sh", "bash"): a pane started as `sh <script>`, and `bash <script>`
    # typed at main's prompt. replace reads the whole command line.
    script = WORK / "build.sh"
    script.write_text("sleep 300\n")
    t("new-session", "-d", "-s", "job", "-c", a, f"sh {script}")
    t("send-keys", "-t", "=main:0", f"bash {script}", "Enter")
    until("main running bash", lambda: pane_command("=main:0") == "bash")
    assert pane_command("=job:0") == "sh", pane_command("=job:0")
    r = cli("replace", "only-api")
    assert r.returncode == 1, r.stdout + r.stderr
    assert f"main:0.0 bash {script}" in r.stdout, r.stdout
    # tmux starts a pane's command by `sh -c`, which may stay in front of it
    assert re.search(rf"job:0\.0 (sh -c )?sh {re.escape(str(script))}", r.stdout)
    assert sorted(windows()) == ["api", "job", "main", "solo", "tmux-history"]
    passed("replace reads the whole command line: a script run by sh or bash is busy")
    t("kill-session", "-t", "=job")
    t("respawn-pane", "-k", "-t", "=main:0", "-c", main)

    pid = t("display", "-p", "#{pid}").strip()
    inside = {
        **ENV,
        "TMUX": f"{SOCKET},{pid},0",
        "TMUX_PANE": t("display", "-p", "-t", "=solo:0", "#{pane_id}").strip(),
    }
    r = cli("replace", "only-api", env=inside)
    assert r.returncode == 1, r.stdout + r.stderr
    assert "this runs in session 'solo'" in r.stdout, r.stdout
    passed("replace refuses to close the session it runs in")
    r = cli("replace", "only-api")
    assert r.returncode == 0, r.stdout + r.stderr
    assert sorted(windows()) == ["api", "tmux-history"], windows()
    passed("replace closes main and solo, keeps api and tmux-history")

    # a directory gone
    (STATE / "gone.txt").write_text(f"session new\n  window {D / 'missing'}\n")
    r = cli("restore", "gone")
    assert r.returncode == 1, r.stdout + r.stderr
    assert f"new: {D / 'missing'}" in r.stdout, r.stdout
    assert "new" not in windows(), windows()
    passed("restore with a directory gone: refused, naming it, nothing created")


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
try:
    check("end to end", run_end_to_end)
finally:
    tmux("kill-server")
log(f"{passes} passed, {failures} failed")
if failures:
    log(f"kept work dir: {WORK}")
else:
    shutil.rmtree(WORK)
shutil.rmtree(SOCKETS, ignore_errors=True)
sys.exit(1 if failures else 0)

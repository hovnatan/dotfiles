r"""The logic behind scripts/ghostty_tmux_arrangement.sh, on Ghostty's AppleScript.

Save which tmux sessions Ghostty's windows hold, and bring them back in new
windows. Only tmux tabs are saved: a plain shell has nothing to come back to.

  save [<name>]    every window (<name> defaults to "all")
  snapshot         every window, as "auto-<UTC YYYYMMDD_HHMMSS>", then all but
                   the newest 2016 (two weeks) removed; run every 10 minutes
                   by Hammerspoon (home/.hammerspoon/ghostty_snapshots.lua)
  restore [<name>] the saved windows, beside what is open
  replace [<name>] the saved windows, in place of every window open

    Ghostty (AppleScript) --> per terminal: id, tty, name (read_windows)
      |
      v  line_of(): what each terminal is
    tty is a local tmux client  -> tmux [-L <socket>] new-session -A -s <session>
      (tmux list-clients)            -c <its directory>
    ssh, title "[<shown>]" or   -> LC_TMUX_ATTACH=<socket>:<session> \
      "(<host>) [<shown>]"           ssh -o SendEnv=LC_TMUX_ATTACH <login>
                                   (the host is asked which socket: attach_for)
    anything else               -> skipped, and logged
      |
      v
    ~/.local/state/ghostty_tmux_arrangements/<name>.txt: plain text, to read
    or edit by hand; a "window:" line per window, then one command per tab

  restore: the file --> plan_restore() --> a new window per block, a tab per
           line, each line typed into the tab's shell, so leaving tmux leaves
           a local shell --> wait_landed(): each title shows its session,
           else the restore fails, naming them

Ghostty not running: restore and replace launch it by open_clean.sh
(launch()), with a Dock launch's environment, never the caller's, and close
its startup window once theirs land; save and snapshot fail, as a new
Ghostty has nothing to save.

What restore does with a session (plan_restore):

    already open in Ghostty      skipped: a second client adds nothing
    local, alive                 attached
    local, gone (a reboot ended  created empty in its saved directory, and
      the tmux server)           logged by name: its programs are not back
    local, gone, directory gone  an error before anything opens
    over ssh, gone               the far side refuses; the tab fails to land

replace opens before it closes, so a failure costs no window:

    parse the file, plan_restore   a bad file or a dead directory fails here
    refuse under Ghostty           closing its windows would end this run
    Ghostty not running?           launched by open_clean.sh; its startup
                                   window is the only one to close
    refuse a busy terminal         one outside tmux, running something, would
                                   die with its window (busy_terminals)
    open the saved windows, wait   a session that never lands fails here, the
                                   windows that were open left as they were
    close the windows of before    their tmux clients go; the sessions stay,
                                   attached from the new windows

The terminal's own name is read, not its tab's or window's: Ghostty puts its
bell mark in those, before the title, which would hide a session.

Lines typed into a tab are for fish, the shell of the default profile.
Imported without running (scripts/tests/ghostty_tmux_arrangement_test.py) it
only defines its functions.
"""

# A script beside its shell wrapper, no license header, as in scripts/tests.
# ruff: noqa: INP001, CPY001

import os
import re
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tmux_arrangement
from tmux_arrangement import (
    LOG,
    SNAPSHOT_KEEP,
    SNAPSHOT_PREFIX,
    ArrangementError,
    Client,
    Lookup,
    alive,
    ancestor,
    attach_for,
    attach_request,
    check_local,
    local_clients,
    local_line,
    local_request,
    log,
    ps_parent,
    remote_lookup,
    run,
    snapshot_name,
    ssh_command,
)

DIR = Path.home() / ".local/state/ghostty_tmux_arrangements"
OPEN_CLEAN = Path(__file__).resolve().parents[1] / "macos/open_clean.sh"
IDLE_SHELLS = frozenset({"bash", "fish", "sh", "zsh"})
LANDING_TIMEOUT = 30.0  # s for every restored tab to show its session
OSASCRIPT_TIMEOUT = 30  # s; it takes under a second, longer while macOS asks
PROGRESS_EVERY = 5.0  # s between the lines a restore logs while it waits
LAUNCH_TIMEOUT = 30.0  # s for a launched Ghostty to show its startup window
USAGE = (
    "usage: ghostty_tmux_arrangement.sh save [<name>] | restore [<name>]"
    " | replace [<name>] | snapshot"
)
MAX_ARGS = 2  # <command> <name>
# "(local) [main]", "(vm) [main]" for an ssh client, "[main]" before any attach
# report (~/.config/tmux/tmux.conf's set-titles-string, which reads @title_host).
TITLE = re.compile(r"(?:\(\S+\) )?\[(.+)\]")

# The fields of one terminal a line, " " for the unit separator shown here:
#   window <id>
#   terminal <id> /dev/ttys005 [vm/api]
# Each list is fetched whole, as ids, by `get`: a bare `repeat with w in windows`
# asks for window 1, 2, 3... of a list Ghostty reorders meanwhile, which doubled
# one window and dropped another in 4 of 25 reads (2026-11-04).
READ_WINDOWS = """
with timeout of 20 seconds
  set sep to character id 31
  set out to ""
  tell application "Ghostty"
    repeat with w in (get windows)
      set out to out & "window" & sep & (id of w) & linefeed
      repeat with t in (get tabs of w)
        repeat with s in (get terminals of t)
          set out to out & "terminal" & sep & (id of s) & sep & (tty of s)
          set out to out & sep & (name of s) & linefeed
        end repeat
      end repeat
    end repeat
  end tell
  return out
end timeout
"""
# Opens a tab typing `line`, in window `winId`, or a new window if that is "".
OPEN_TAB = """
on run argv
  set winId to item 1 of argv
  set typed to item 2 of argv
  with timeout of 20 seconds
    tell application "Ghostty"
      set cfg to new surface configuration
      set initial input of cfg to typed & linefeed
      if winId is "" then
        set w to new window with configuration cfg
        set t to selected tab of w
      else
        set w to first window whose id is winId
        set t to new tab in w with configuration cfg
      end if
      return (id of w) & character id 31 & (id of focused terminal of t)
    end tell
  end timeout
end run
"""
CLOSE_WINDOW = """
on run argv
  with timeout of 20 seconds
    tell application "Ghostty"
      close window (first window whose id is (item 1 of argv))
    end tell
  end timeout
end run
"""
ACTIVATE = """
on run argv
  with timeout of 20 seconds
    tell application "Ghostty"
      activate window (first window whose id is (item 1 of argv))
    end tell
  end timeout
end run
"""


@dataclass
class Terminal:
    """What Ghostty reports of one terminal."""

    id: str
    tty: str
    name: str


@dataclass
class Window:
    """A Ghostty window: its terminals, every tab's, in order."""

    id: str
    terminals: list[Terminal]


@dataclass
class Opening:
    """A tab to open: the line to type, and the session it should come to show."""

    line: str
    session: str


# --- what a terminal is: pure ---------------------------------------------------


def title_session(title: str) -> str | None:
    """Return the name a terminal's title shows for its tmux session, or None.

    "[vm/api/docs]" -> "vm/api/docs"; "(vm) [main]" -> "main";
    "(local) [main]" -> "main"; "fish:~" -> None.
    """
    m = TITLE.fullmatch(title)
    return m[1] if m else None


def line_of(
    index: int,
    terminal: Terminal,
    client: Client | None,
    foreground: str,
    lookup: Lookup,
) -> str | None:
    """Return the saved line of terminal number `index`, or None if it is no tmux.

    `client` is the local tmux client on its tty, `foreground` its foreground
    command line. A tmux tab whose ssh cannot be replayed is an error: skipping
    it would lose the session without a word.
    """
    if client:
        return local_line(client)
    if not is_ssh(foreground):
        return None
    shown = title_session(terminal.name)
    if shown is None:
        return None
    try:
        login = ssh_command.interactive(foreground)
    except ssh_command.NotReplayableError as e:
        msg = f"tab {index}: ssh command line cannot be replayed: {e}"
        raise ArrangementError(msg) from e
    return attach_for(index, login, shown, lookup)


def is_ssh(command: str) -> bool:
    """Tell whether a command line runs ssh: "/usr/bin/ssh vm" -> True, "" -> False."""
    return bool(command) and Path(command.split(maxsplit=1)[0]).name == "ssh"


def idle(command: str) -> bool:
    """Tell whether a tty's foreground command is a shell at its prompt, or nothing.

    "-fish" and "/bin/zsh" are; "" is; "fish build.fish" and "vim" are not. A
    shell that shows arguments is running them.
    """
    words = command.split()
    return not words or (
        len(words) == 1 and Path(words[0]).name.lstrip("-") in IDLE_SHELLS
    )


def busy_terminals(
    windows: list[Window],
    clients: dict[str, Client],
    foreground: Callable[[str], str],
) -> list[str]:
    """Return what closing `windows` would kill, said a terminal each.

    A tmux tab, local or over ssh, keeps its session when its window closes,
    and a shell at its prompt holds nothing: anything else is lost.
        Terminal("1", "/dev/ttys005", "vim"), foreground "vim x" -> ["'vim' (vim x)"]
    """
    busy = []
    for window in windows:
        for terminal in window.terminals:
            if terminal.tty in clients:
                continue
            command = foreground(terminal.tty)
            over_ssh = is_ssh(command) and title_session(terminal.name) is not None
            if not over_ssh and not idle(command):
                busy.append(f"{terminal.name!r} ({command})")
    return busy


def foreground_of(ps_output: str) -> str:
    r"""Return the foreground command of a tty, an ssh one first, from `ps` output.

    "Ss  -fish\nS+  ssh vm\n" -> "ssh vm"; "S+  -fish\n" -> "-fish"; "" -> "".
    A foreground process has a "+" in its state. There can be several, a
    pipeline; ssh is what a tab is saved by, so it wins.
    """
    found = []
    for line in ps_output.splitlines():
        stat, _, command = line.strip().partition(" ")
        if "+" in stat:
            found.append(command.strip())
    for command in found:
        if is_ssh(command):
            return command
    return found[0] if found else ""


def parse_windows(text: str) -> list[Window]:
    """Return the windows of READ_WINDOWS's output; any other line is an error."""
    windows: list[Window] = []
    for line in text.splitlines():
        kind, *fields = line.split("\x1f")
        if kind == "window" and len(fields) == 1:
            windows.append(Window(fields[0], []))
        elif kind == "terminal" and len(fields) == 3 and windows:  # noqa: PLR2004
            windows[-1].terminals.append(Terminal(*fields))
        elif line:
            msg = f"Ghostty's window list has a line of no known shape: {line!r}"
            raise ArrangementError(msg)

    # A window twice means another went unread: a save would lose its session.
    ids = [w.id for w in windows]
    if len(set(ids)) != len(ids):
        msg = f"Ghostty listed a window twice, so the read missed one: {ids}"
        raise ArrangementError(msg)
    return windows


# --- the file: pure -------------------------------------------------------------


def render(name: str, saved_at: str, windows: list[list[str]]) -> str:
    """Return the file's text for `windows`, a list of lines per window."""
    out = [
        f'# Ghostty tmux arrangement "{name}", saved {saved_at}; restore with:',
        f"#   ~/.dotfiles/scripts/ghostty_tmux_arrangement.sh restore {name}",
        "# Each window: one command per tab. The first window is restored in front.",
    ]
    for lines in windows:
        out += ["", "window:", *lines]
    return "\n".join(out) + "\n"


def parse_file(text: str) -> list[list[str]]:
    r"""Return the lines of each window of the file's text.

    "window:\nLC_TMUX_ATTACH=...\n" -> [["LC_TMUX_ATTACH=..."]]. A line before
    the first "window:", a line that is no tmux request, or a window with no
    tabs is an error: a hand edit gone wrong, caught before any tab opens.
    """
    windows: list[list[str]] = []
    for n, line in enumerate(text.splitlines(), 1):
        if line == "window:":
            windows.append([])
        elif line and not line.startswith("#"):
            if not windows:
                msg = f'line {n} is a command before any "window:" line: {line}'
                raise ArrangementError(msg)
            try:
                known = attach_request(line) or local_request(line)
            except ArrangementError as e:
                msg = f"line {n} {e}"
                raise ArrangementError(msg) from e
            if not known:
                msg = f"line {n} attaches no tmux session: {line}"
                raise ArrangementError(msg)
            windows[-1].append(line)
    if not windows:
        msg = 'no "window:" line'
        raise ArrangementError(msg)
    for i, lines in enumerate(windows, 1):
        if not lines:
            msg = f"window {i} has no tabs"
            raise ArrangementError(msg)
    return windows


# --- what a restore does: pure --------------------------------------------------


def session_key(line: str) -> tuple[str, ...]:
    """Return what makes two saved lines the same session.

    A remote line is its own key, the host being part of it. A local line is
    its socket and session, not its directory, which may have moved on.
    """
    client = local_request(line)
    return ("local", client.socket, client.session) if client else ("remote", line)


def session_of(line: str) -> str:
    """Return the session a saved line brings back."""
    client = local_request(line)
    if client:
        return client.session
    request = attach_request(line)
    if request is None:
        msg = f"attaches no tmux session: {line}"
        raise ArrangementError(msg)
    return request[1]


def plan_restore(
    windows: list[list[str]],
    open_lines: list[str],
    alive: Callable[[Client], bool],
    is_dir: Callable[[str], bool],
) -> list[list[Opening]]:
    """Return the tabs to open per window: see the docstring's table.

    A window whose sessions are all open is dropped. A local session to
    create in a directory that is gone is an error, raised before any tab
    opens, and `alive` and `is_dir` are asked only of what will be opened.
    """
    open_keys = {session_key(line) for line in open_lines}
    plan = []
    for lines in windows:
        tabs = []
        for line in lines:
            if session_key(line) in open_keys:
                log(f"already open, skipped: {session_of(line)}")
                continue
            check_local(line, alive, is_dir)
            tabs.append(Opening(line, session_of(line)))
        if tabs:
            plan.append(tabs)
    return plan


def landed(session: str, title: str) -> bool:
    """Tell whether a title shows `session`.

    ("api/docs", "(vm) [api/docs]") -> True; ("api", "fish:~") -> False
    """
    return title_session(title) == session


# --- Ghostty, tmux and ps -------------------------------------------------------


def osascript(script: str, *args: str) -> str:
    """Run AppleScript `script` with `args`; its failure is an error, saying why."""
    done = run(["osascript", "-e", script, *args], OSASCRIPT_TIMEOUT)
    if done.returncode != 0:
        hint = ""
        if "-1743" in done.stderr:
            hint = (
                "; allow this app to control Ghostty in System Settings >"
                " Privacy & Security > Automation"
            )
        msg = f"osascript failed: {done.stderr.strip()}{hint}"
        raise ArrangementError(msg)
    return done.stdout.rstrip("\n")


def ghostty_running() -> bool:
    """Tell whether Ghostty runs."""
    return run(["pgrep", "-x", "ghostty"], OSASCRIPT_TIMEOUT).returncode == 0


def require_ghostty() -> None:
    """Fail unless Ghostty runs: `tell application` would launch it instead.

    For save and snapshot, where a launched Ghostty would have nothing to
    save; restore and replace launch it themselves (launch()). The message
    asks for no launch: "start it first" once got a bare `open -a Ghostty`.
    """
    if not ghostty_running():
        msg = "Ghostty is not running, so it has no windows to save"
        raise ArrangementError(msg)


def read_windows() -> list[Window]:
    """Return Ghostty's windows, the front one first."""
    return parse_windows(osascript(READ_WINDOWS))


def foreground(tty: str) -> str:
    """Return the foreground command line of `tty`, "" if it has none."""
    short = tty.removeprefix("/dev/")
    return foreground_of(run(["ps", "-t", short, "-o", "stat=,command="], 10).stdout)


def saved_lines(windows: list[Window], lookup: Lookup) -> list[list[str]]:
    """Return the lines of every window, those with no tmux tab left out."""
    clients = local_clients()
    out = []
    index = 0
    for w in windows:
        lines = []
        for t in w.terminals:
            index += 1
            fg = foreground(t.tty)
            line = line_of(index, t, clients.get(t.tty), fg, lookup)
            if line is None:
                log(f"tab {index}: no tmux ({t.name!r}, running {fg!r}), skipped")
            else:
                log(f"tab {index}: {line}")
                lines.append(line)
        if lines:
            out.append(lines)
    return out


def write(name: str, windows: list[list[str]]) -> None:
    """Write arrangement `name`, by a rename so a kill cannot leave half a file."""
    DIR.mkdir(parents=True, exist_ok=True)
    saved_at = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ}"
    file = DIR / f"{name}.txt"
    temp = file.with_suffix(".tmp")
    temp.write_text(render(name, saved_at, windows))
    temp.replace(file)
    log(f"saved {file}")


def save(name: str) -> None:
    """Save every tmux tab as `name`; none at all is an error, nothing to save."""
    windows = saved_lines(read_windows(), remote_lookup(unattended=False))
    if not windows:
        msg = "no Ghostty tab holds a tmux session"
        raise ArrangementError(msg)
    write(name, windows)


def snapshot() -> None:
    """Save a new snapshot, then drop all but the newest SNAPSHOT_KEEP.

    Windows with no tmux at all are no failure, and write nothing: the last
    snapshot that held something stays the newest.
    """
    windows = saved_lines(read_windows(), remote_lookup(unattended=True))
    if not windows:
        log("no Ghostty tab holds a tmux session: nothing saved")
        return
    write(snapshot_name(datetime.now(UTC)), windows)
    names = [p.stem for p in DIR.glob(f"{SNAPSHOT_PREFIX}*.txt")]
    stale = tmux_arrangement.stale_snapshots(names, DIR)
    for name in stale:
        (DIR / f"{name}.txt").unlink()
    log(f"removed {len(stale)} snapshots past the newest {SNAPSHOT_KEEP}")


def load(name: str) -> list[list[str]]:
    """Return the windows of arrangement `name`; a missing or bad file is an error."""
    file = DIR / f"{name}.txt"
    if not file.exists():
        names = sorted(p.stem for p in DIR.glob("*.txt")) if DIR.exists() else []
        kept = [n for n in names if not n.startswith(SNAPSHOT_PREFIX)]
        msg = (
            f"no arrangement {name!r}: {file} does not exist; saved: {kept or '(none)'}"
            f" and {len(names) - len(kept)} snapshots"
        )
        raise ArrangementError(msg)
    try:
        return parse_file(file.read_text())
    except ArrangementError as e:
        msg = f"{file}: {e}"
        raise ArrangementError(msg) from e


def open_tabs(plan: list[list[Opening]]) -> tuple[list[str], dict[str, str]]:
    """Open `plan`; return the windows made and {terminal id: its session}."""
    made = []
    waiting = {}
    for tabs in plan:
        window = ""
        for tab in tabs:
            window, terminal = osascript(OPEN_TAB, window, tab.line).split("\x1f")
            waiting[terminal] = tab.session
            log(f"opened {tab.session} in {window}")
        made.append(window)
    return made, waiting


def wait_landed(waiting: dict[str, str]) -> None:
    """Wait for each opened terminal's title to show its session, else fail."""
    left = dict(waiting)
    start = time.monotonic()
    said = start
    while left:
        names = {t.id: t.name for w in read_windows() for t in w.terminals}
        left = {
            t: s for t, s in left.items() if t not in names or not landed(s, names[t])
        }
        now = time.monotonic()
        if left and now - start > LANDING_TIMEOUT:
            stuck = ", ".join(
                f"{s} (title {names.get(t, 'its tab closed')!r})"
                for t, s in left.items()
            )
            msg = f"{len(left)} tabs never showed their session: {stuck}"
            raise ArrangementError(msg)
        if left and now - said >= PROGRESS_EVERY:
            log(f"waiting on {len(left)} tabs: {', '.join(left.values())}")
            said = now
        if left:
            time.sleep(0.5)


def restore(name: str) -> None:
    """Open the saved windows beside what is open, and see each session land.

    Ghostty not running is launched here, by launch() (open_clean.sh), not
    left to the caller: a caller's bare `open -a Ghostty` hands Ghostty its
    shell's environment, and every tab after inherits it (2026-11-07, an
    agent's: each new claude ran with transcripts off). The plan comes first,
    so a bad file or a dead directory fails before the launch; the startup
    window, an empty shell, is closed once the sessions land, and left if
    they do not.
    """
    windows = load(name)
    running = ghostty_running()
    current = (
        saved_lines(read_windows(), remote_lookup(unattended=False)) if running else []
    )
    plan = plan_restore(
        windows,
        [line for lines in current for line in lines],
        alive,
        os.path.isdir,
    )
    if not plan:
        log(f"every session of {name} is already open")
        return
    startup = [] if running else launch()

    made, waiting = open_tabs(plan)
    wait_landed(waiting)
    for window in startup:
        osascript(CLOSE_WINDOW, window.id)
        log(f"closed the startup window {window.id}")
    osascript(ACTIVATE, made[0])
    log(f"restored {len(waiting)} tabs in {len(made)} windows from {name}")


def launch() -> list[Window]:
    """Launch Ghostty, with a Dock launch's environment; return its startup windows."""
    log("launching Ghostty")
    done = run([str(OPEN_CLEAN), "-a", "Ghostty"], LAUNCH_TIMEOUT)
    if done.returncode != 0:
        msg = f"launching Ghostty failed: {done.stderr.strip()}"
        raise ArrangementError(msg)

    # Its windows are asked for only once it runs: `tell application` before
    # that would be a second way to launch it, with this run's environment.
    deadline = time.monotonic() + LAUNCH_TIMEOUT
    while time.monotonic() < deadline:
        windows = read_windows() if ghostty_running() else []
        if windows:
            return windows
        time.sleep(0.5)
    msg = (
        f"Ghostty showed no window {LAUNCH_TIMEOUT:g} s after its launch;"
        " is initial-window off in its config?"
    )
    raise ArrangementError(msg)


def windows_to_replace() -> list[Window]:
    """Return the windows a replace will close, Ghostty launched if it is not running.

    A terminal that would lose a running program is an error, naming it. A
    launch's startup window is left out of that check: it holds nothing yet,
    and its shell may not have reached a prompt.
    """
    if not ghostty_running():
        return launch()
    windows = read_windows()
    if busy := busy_terminals(windows, local_clients(), foreground):
        msg = (
            f"closing every window would kill {', '.join(busy)}: finish or close"
            " them first, or `restore` to add the windows to those open"
        )
        raise ArrangementError(msg)
    return windows


def replace(name: str) -> None:
    """Open the saved windows in place of every window open: see the docstring."""
    # Every check comes before anything opens: past them a failure leaves
    # windows to clean up, and past the close there is no going back.
    windows = load(name)
    if under := ancestor(os.getpid(), ps_parent, lambda exe: exe == "ghostty"):
        msg = (
            f"runs under Ghostty ({under}), so closing its windows would end it"
            " before the restore; run it from a tmux pane or another terminal"
            " app, or `restore` to add the windows to those open"
        )
        raise ArrangementError(msg)
    plan = plan_restore(windows, [], alive, os.path.isdir)
    old = windows_to_replace()

    made, waiting = open_tabs(plan)
    try:
        wait_landed(waiting)
    except ArrangementError as e:
        msg = f"{e}; the {len(old)} windows open before are left, beside the new ones"
        raise ArrangementError(msg) from e

    for window in old:
        osascript(CLOSE_WINDOW, window.id)
        log(f"closed {window.id}")
    osascript(ACTIVATE, made[0])
    log(f"replaced {len(old)} windows with {len(made)} from {name}")


def main() -> None:
    """Parse argv (<event log> <command> [<name>]) and act."""
    LOG.append(Path(sys.argv[1]))
    args = sys.argv[2:]
    command, name = [*args, None, None][:2]
    if (
        command not in ("save", "restore", "replace", "snapshot")
        or len(args) > MAX_ARGS
        or (command == "snapshot" and name)
    ):
        log(f"ERROR: {USAGE}")
        sys.exit(1)
    name = name or "all"
    if not re.fullmatch(r"[\w.-]+", name, re.ASCII):
        log(f"ERROR: name {name!r}: use letters, digits, '.', '_', '-'")
        sys.exit(1)
    # Snapshots are pruned by this prefix: a save under it would be pruned,
    # or, not named by a time, stop every snapshot's pruning.
    if command == "save" and name.startswith(SNAPSHOT_PREFIX):
        log(f"ERROR: name {name!r}: {SNAPSHOT_PREFIX!r} is for snapshots alone")
        sys.exit(1)

    # An ArrangementError is a finding about the windows, the file or
    # Ghostty, said in one line; anything else is a bug and keeps its traceback.
    try:
        if command == "replace":
            replace(name)
        elif command == "restore":
            restore(name)
        else:
            require_ghostty()
            if command == "save":
                save(name)
            else:
                snapshot()
    except ArrangementError as e:
        log(f"ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

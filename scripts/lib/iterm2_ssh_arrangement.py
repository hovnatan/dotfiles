# /// script
# requires-python = ">=3.11"
# dependencies = ["iterm2==2.25"]
# ///
r"""The logic behind scripts/iterm2_ssh_arrangement.sh, on iTerm2's Python API.

Save the tabs of iTerm2's windows as the commands that bring each back, and
restore them into new windows. A tab saved here can be reopened after iTerm2
lost it: a reboot, a Cmd-Q, or an upgrade without session restoration.

  save [<name>]                 every window (<name> defaults to "all")
  save <name> <title prefix>    the one window whose title starts so
    iTerm2 (Python API) --> per window, the key window first: its title
                            template, and per tab: panes, jobName,
                            commandLine, title, path (read_windows)
      |
      v  plan(): what each tab is
    ssh, title "[<session>]" -> remote tmux; which socket holds <session>
                                is asked of the host (one ssh per host)
                                -> LC_TMUX_ATTACH=claude:<session> \
                                     ssh -o SendEnv=LC_TMUX_ATTACH <login>
    ssh, any other title     -> ssh <login>
    anything else            -> cd '<path>' (a local tab; its program is
                                not rerun)
      |
      v
    ~/.local/state/iterm2_ssh_arrangements/<name>.txt: plain text, to read
    or edit by hand; a "window: <title template>" line per window, then one
    command per tab, in tab order (render / parse_file)

  restore [<name>]
    the file --> a new window per "window:" block, a tab per line, each line
                 typed into the tab's shell (as Cmd-T does), so exiting ssh
                 leaves a local shell; its title template set and read back.
                 The first block's window ends up in front, as it was saved.
                 Then each tmux tab is waited on until its title shows its
                 session (wait_attached): a request the far side never acted
                 on leaves a plain shell, which fails the restore by name.

<login> is ssh_command.py's replay of the tab's ssh command line (Cmd-T's
parser): the options and destination, never a remote command or forward.
The "[<session>]" title is ~/.tmux.conf's set-titles-string for an iTerm2
client. A session lives on the default socket or on claude_tmux_run.sh's
"claude" one, and the title does not say which, hence the lookup.

The attach goes through the remote login shell, not a remote command: over
Tailscale SSH a remote command gets a pty that stays root's, and the
client-attached hook (home/.config/tmux/report-attach.sh) cannot write the
iTerm2 host report to it. A plain login runs login(1), which hands the pty
to the user; the login fish then attaches what LC_TMUX_ATTACH names
(home/.config/fish/functions/tmux_attach_requested.fish):

    ssh -t vm tmux -L claude attach -t =x                   pty root's,
                                                            report fails
    LC_TMUX_ATTACH=claude:x ssh -o SendEnv=LC_TMUX_ATTACH vm
                                                            pty the user's,
                                                            report lands

SendEnv, not SetEnv: ssh keeps only the first SetEnv it reads, so one on
the command line would drop the host's own from ~/.ssh/config, while
SendEnv lines add up.

Lines typed into a tab are for fish, the shell of the default profile.
Imported without running (scripts/tests/iterm2_ssh_arrangement_test.py) it
only defines its functions.
"""

# A script beside its shell wrapper, no license header, as in scripts/tests.
# ruff: noqa: CPY001

import asyncio
import re
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import iterm2

# The parser lives beside its first user, Cmd-T's iterm2_api.py.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "home/.hammerspoon"))
import ssh_command

SOCKETS = ("claude", "default")  # tmux_attach_requested.fish accepts these
ATTACH_SEND = "-o SendEnv=LC_TMUX_ATTACH"
ATTACH_TIMEOUT = 30.0  # s for every restored tmux tab to show its session
DIR = Path.home() / ".local/state/iterm2_ssh_arrangements"
USAGE = (
    "usage: iterm2_ssh_arrangement.sh save [<name> [<window title prefix>]]"
    " | restore [<name>]"
)
MAX_ARGS = 3  # save <name> <prefix>
LOG: list[Path] = []  # the run's event log, set by main()


class ArrangementError(Exception):
    """A save or restore that would leave the wrong thing; the message says what."""


@dataclass
class Tab:
    """What iTerm2 reports of one tab, by its first pane."""

    panes: int
    job: str
    command_line: str
    title: str
    path: str


@dataclass
class Plan:
    """What a tab is, before any remote lookup.

    kind "tmux": login and session; "ssh": login; "local": line.
    """

    kind: str
    login: str = ""
    session: str = ""
    line: str = ""


@dataclass
class Saved:
    """A window as the file holds it: its title template and a line per tab."""

    template: str
    lines: list[str]


def render(name: str, saved_at: str, windows: list[Saved]) -> str:
    """Return the file's text for `windows`."""
    out = [
        f'# iTerm2 ssh arrangement "{name}", saved {saved_at}; restore with:',
        f"#   ~/.dotfiles/scripts/iterm2_ssh_arrangement.sh restore {name}",
        "# Each window: its title template (Window > Edit Window Title takes it",
        "# as is), then one command per tab. The first window is restored in front.",
    ]
    for w in windows:
        out += ["", f"window: {w.template}".rstrip(" "), *w.lines]
    return "\n".join(out) + "\n"


def parse_file(text: str) -> list[Saved]:
    r"""Return the windows of the file's text.

    "window: x\nssh vm\n" -> [Saved("x", ["ssh vm"])]. A command before the
    first "window:" line or a window with no tabs is an error: a hand edit
    gone wrong.
    """
    windows: list[tuple[int, Saved]] = []
    for n, line in enumerate(text.splitlines(), 1):
        if m := re.fullmatch(r"window: ?(.*)", line):
            windows.append((n, Saved(m[1], [])))
        elif line and not line.startswith("#"):
            if not windows:
                msg = f'line {n} is a command before any "window:" line: {line}'
                raise ArrangementError(msg)
            windows[-1][1].lines.append(line)
    if not windows:
        msg = 'no "window:" line'
        raise ArrangementError(msg)
    for i, (n, w) in enumerate(windows, 1):
        if not w.lines:
            msg = f"window {i} (line {n}) has no tabs"
            raise ArrangementError(msg)
    return [w for _, w in windows]


def tmux_session(title: str) -> str | None:
    """Return the remote tmux session a tab title shows, or None.

    "[api/docs]" -> "api/docs"; "[ai-agent] " -> "ai-agent" (retitle.sh
    may leave a trailing space); "fish:~" -> None.
    """
    m = re.fullmatch(r"\[(.+)\] ?", title)
    return m[1] if m else None


def tmux(socket: str) -> str:
    """Return the tmux command for `socket`: "tmux" or "tmux -L claude"."""
    return "tmux" if socket == "default" else f"tmux -L {socket}"


def attach_line(login: str, socket: str, session: str) -> str:
    """Return the line that reattaches `session` on `socket`, via the login shell.

    ("ssh -p 2222 vm", "claude", "ai-agent")
        -> "LC_TMUX_ATTACH=claude:ai-agent ssh -o SendEnv=LC_TMUX_ATTACH -p 2222 vm"
    The value is "<socket>:<session>", split at the first ":" on the far
    side; tmux allows no ":" in a session name. LC_ because the stock
    AcceptEnv of sshd (LANG LC_*) passes only those; Tailscale SSH passed
    it as is in a test on this tailnet.
    """
    if not ssh_command.plain(session):
        msg = f"tmux session {session!r} has characters needing quotes; rename it"
        raise ArrangementError(msg)
    first, *rest = login.split()
    words = [f"LC_TMUX_ATTACH={socket}:{session}", first, ATTACH_SEND, *rest]
    return " ".join(words)


def attach_request(line: str) -> tuple[str, str] | None:
    """Return the (socket, session) a saved line asks the far side to attach.

    attach_line's output -> its socket and session; any other line -> None.
    "LC_TMUX_ATTACH=claude:api/docs ssh -o SendEnv=LC_TMUX_ATTACH vm"
        -> ("claude", "api/docs")
    """
    pattern = rf"LC_TMUX_ATTACH=([^:\s]+):(\S+) \S+ {re.escape(ATTACH_SEND)} .+"
    m = re.fullmatch(pattern, line)
    return (m[1], m[2]) if m else None


def fish_quote(s: str) -> str:
    r"""Quote `s` for fish: inside '...' only \ and ' are special."""
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def plan(tab: Tab, index: int) -> Plan:
    """Return what tab number `index` is.

    A split tab or an ssh line ssh_command.py will not re-parse is an error:
    saving it as something else would restore the wrong thing.
    """
    if tab.panes != 1:
        msg = f"tab {index} has {tab.panes} panes; only one-pane tabs can be saved"
        raise ArrangementError(msg)
    if tab.job != "ssh":
        if not tab.path:
            msg = f"tab {index}: iTerm2 reports no directory for it"
            raise ArrangementError(msg)
        return Plan("local", line=f"cd {fish_quote(tab.path)}")
    try:
        login = ssh_command.interactive(tab.command_line)
    except ssh_command.NotReplayableError as e:
        msg = f"tab {index}: ssh command line cannot be replayed: {e}"
        raise ArrangementError(msg) from e
    if session := tmux_session(tab.title):
        return Plan("tmux", login=login, session=session)
    return Plan("ssh", login=login)


def parse_sessions(text: str) -> dict[str, list[str]]:
    r"""Return {session: [sockets]} from the `tmux ls` output of every socket.

    "claude ai-agent\ndefault main\n"
        -> {"ai-agent": ["claude"], "main": ["default"]}
    Lines of any other shape ("no server running on ...") are what a socket
    with no server prints; they are kept only for the error in lines().
    """
    found: dict[str, list[str]] = {}
    for line in text.splitlines():
        socket, _, session = line.partition(" ")
        if socket in SOCKETS and session:
            found.setdefault(session, []).append(socket)
    return found


def list_sessions_argv(login: str) -> list[str]:
    """Return the argv that lists every socket's sessions on the host of `login`.

    The remote command is one word for ssh; its single quotes read the same
    in a remote sh and a remote fish.
    """
    remote = "; ".join(
        f"{tmux(socket)} ls -F '{socket} #{{session_name}}'" for socket in SOCKETS
    )
    return [*login.split(), remote]


Lookup = Callable[[str], tuple[dict[str, list[str]], str]]


def lines(plans: list[Plan], lookup: Lookup) -> list[str]:
    """Return the saved lines; lookup(login) gives a host's sessions and raw output."""
    out = []
    for i, p in enumerate(plans, 1):
        if p.kind == "local":
            out.append(p.line)
            continue
        if p.kind == "ssh":
            out.append(p.login)
            continue
        found, raw = lookup(p.login)
        sockets = found.get(p.session, [])
        if not sockets:
            msg = (
                f"tab {i}: tmux session {p.session!r} is on no socket"
                f" ({', '.join(SOCKETS)}) of `{p.login}`; its tmux ls said:\n{raw}"
            )
            raise ArrangementError(msg)
        if len(sockets) > 1:
            msg = (
                f"tab {i}: tmux session {p.session!r} is on sockets"
                f" {' and '.join(sockets)} of `{p.login}`; rename one"
            )
            raise ArrangementError(msg)
        out.append(attach_line(p.login, sockets[0], p.session))
    return out


# --- the script ----------------------------------------------------------------


def log(msg: str) -> None:
    """Print a UTC-stamped line and append it to the run's event log."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    print(line, flush=True)  # noqa: T201
    with LOG[0].open("a") as f:
        f.write(line + "\n")


async def read_windows(
    app: iterm2.App,
    prefix: str | None,
) -> list[tuple[str, list[Tab]]]:
    r"""Return every window, the key one first, or the one titled `prefix`...

    as (title template, tabs). The template is the raw titleOverrideFormat
    ("ai-agent \(currentTab.currentSession.name)"), not the title it
    renders; jobName and commandLine are the local foreground job, ssh for
    an ssh tab whatever runs on the far side.
    """
    windows = list(app.windows)
    key = app.current_window
    if key in windows:
        windows.remove(key)
        windows.insert(0, key)
    if prefix is not None:
        titles = [await w.async_get_variable("titleOverride") for w in windows]
        windows = [
            w for w, t in zip(windows, titles, strict=True) if t.startswith(prefix)
        ]
        if len(windows) != 1:
            msg = (
                f"{len(windows)} windows have a title starting with {prefix!r};"
                f" titles: {titles}"
            )
            raise ArrangementError(msg)
    if not windows:
        msg = "iTerm2 has no window"
        raise ArrangementError(msg)

    out = []
    for w in windows:
        template = await w.async_get_variable("titleOverrideFormat") or ""
        tabs = []
        for t in w.tabs:
            # all_sessions, not sessions: the latter leaves out the panes
            # behind a maximized one, and such a tab would pass as one pane.
            panes = t.all_sessions
            s = panes[0]
            facts = [
                await s.async_get_variable(v)
                for v in ("jobName", "commandLine", "name", "path")
            ]
            # Every one is set for a live session: None means iTerm2 renamed
            # or dropped the variable.
            if not all(isinstance(f, str) for f in facts):
                msg = (
                    f"iTerm2 reported {facts} for jobName, commandLine, name, path"
                    f" of {s.session_id}"
                )
                raise ArrangementError(msg)
            tabs.append(Tab(len(panes), *facts))
        out.append((template, tabs))
    return out


def remote_lookup() -> Lookup:
    """Return a lookup asking each host once which tmux sockets hold which sessions."""
    cache: dict[str, tuple[dict[str, list[str]], str]] = {}

    def lookup(login: str) -> tuple[dict[str, list[str]], str]:
        if login not in cache:
            log(f"asking `{login}` which tmux sockets hold which sessions")
            # tmux ls exits 1 for a socket with no server, an empty socket,
            # so only ssh's own failure (255) is one.
            done = subprocess.run(  # noqa: S603 - argv from a plain-word login
                list_sessions_argv(login),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
            if done.returncode == 255:  # noqa: PLR2004 - ssh's own error exit
                msg = f"`{login}` failed to connect:\n{done.stdout}"
                raise ArrangementError(msg)
            cache[login] = (parse_sessions(done.stdout), done.stdout)
        return cache[login]

    return lookup


async def save(app: iterm2.App, name: str, prefix: str | None) -> None:
    """Save every window (or the one titled `prefix`...) as arrangement `name`."""
    windows = await read_windows(app, prefix)
    which = f"the window titled {prefix!r}..." if prefix else "every window"
    log(f"save {name}: {len(windows)} windows ({which})")

    # Any tab that cannot be saved fails the whole save, naming its window:
    # a file missing a window would restore less than was there, silently.
    lookup = remote_lookup()
    saved = []
    for wi, (template, tabs) in enumerate(windows, 1):
        try:
            got = lines([plan(t, i) for i, t in enumerate(tabs, 1)], lookup)
        except ArrangementError as e:
            msg = f"window {wi} (title template {template!r}): {e}"
            raise ArrangementError(msg) from e
        saved.append(Saved(template, got))
        log(f"window {wi}: {len(got)} tabs, title template {template!r}")
        for i, line in enumerate(got, 1):
            log(f"  tab {i}: {line}")

    # Written beside its final name and renamed into place, so a failed save
    # never leaves half a file where a good one was.
    DIR.mkdir(parents=True, exist_ok=True)
    file = DIR / f"{name}.txt"
    tmp = file.with_suffix(".txt.tmp")
    tmp.write_text(render(name, f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ}", saved))
    tmp.replace(file)
    log(f"saved {file}")


async def restore(connection: iterm2.Connection, name: str) -> None:
    """Open a new window per saved one, the first saved one in front."""
    file = DIR / f"{name}.txt"
    if not file.exists():
        names = sorted(p.stem for p in DIR.glob("*.txt")) if DIR.exists() else []
        msg = (
            f"no arrangement {name!r}: {file} does not exist;"
            f" saved ones: {names or '(none)'}"
        )
        raise ArrangementError(msg)
    try:
        windows = parse_file(file.read_text())
    except ArrangementError as e:
        msg = f"{file}: {e}"
        raise ArrangementError(msg) from e

    # Last window first, the first one activated at the end: it was the
    # key window when saved. Each title is read back, as a window left with
    # the wrong name is a failure, not a skip.
    opened = []
    attaching: list[tuple[str, str, iterm2.Session]] = []
    for wi in reversed(range(len(windows))):
        w = windows[wi]
        window = await iterm2.Window.async_create(connection)
        if window is None or window.current_tab is None:
            msg = f"iTerm2 made no window for saved window {wi + 1}"
            raise ArrangementError(msg)
        for i, line in enumerate(w.lines):
            tab = window.current_tab if i == 0 else await window.async_create_tab()
            if tab is None or tab.current_session is None:
                msg = f"iTerm2 made no tab {i + 1} in window {wi + 1}"
                raise ArrangementError(msg)
            await tab.current_session.async_send_text(line + "\n")
            log(f"window {wi + 1} tab {i + 1}: {line}")
            if request := attach_request(line):
                attaching.append(
                    (f"window {wi + 1} tab {i + 1}", request[1], tab.current_session),
                )
        if w.template:
            await window.async_set_title(w.template)
            got = await window.async_get_variable("titleOverrideFormat")
            if got != w.template:
                msg = (
                    f"window {wi + 1}: title template reads back {got!r},"
                    f" want {w.template!r}"
                )
                raise ArrangementError(msg)
        log(f"window {wi + 1} restored ({window.window_id}): {w.template!r}")
        opened.append(window)
    await opened[-1].async_activate()
    await wait_attached(attaching)
    log(f"restored {name}: {len(windows)} windows")


async def wait_attached(
    tabs: list[tuple[str, str, iterm2.Session]],
    timeout: float = ATTACH_TIMEOUT,
    poll: float = 0.5,
) -> None:
    """Wait until each (label, session, iTerm2 session) shows "[<session>]".

    The title is ~/.tmux.conf's set-titles-string for an iTerm2 client, so
    it shows the session once the far side's login fish has exec'd tmux.
    Still a shell's title at `timeout`: the request was dropped on the way
    or not acted on, and the restore fails naming the tab, rather than
    leaving a plain shell where a session was saved.
    """
    waiting = list(tabs)
    log(f"waiting up to {timeout:g} s for {len(waiting)} tmux tabs to attach")
    deadline = asyncio.get_running_loop().time() + timeout
    titles: dict[str, str] = {}
    while waiting:
        for tab in list(waiting):
            label, session, iterm_session = tab
            titles[label] = await iterm_session.async_get_variable("name") or ""
            if tmux_session(titles[label]) == session:
                log(f"{label}: attached {session}")
                waiting.remove(tab)
        if waiting and asyncio.get_running_loop().time() >= deadline:
            lines = [
                f"  {label}: want [{session}], title reads {titles[label]!r}"
                for label, session, _ in waiting
            ]
            msg = (
                f"{len(waiting)} tmux tabs did not attach in {timeout:g} s:\n"
                + "\n".join(lines)
                + "\nOn the far side, the tmux_attach_requested event log"
                " (~/.dotfiles/.logs/*_tmux_attach_requested/events.log) shows"
                " each request received: none means LC_TMUX_ATTACH never arrived"
                " (sshd AcceptEnv, or the host runs no fish with"
                " tmux_attach_requested: dotup it); a line means tmux refused it."
            )
            raise ArrangementError(msg)
        if waiting:
            await asyncio.sleep(poll)


def main() -> None:
    """Parse argv (<event log> <command> [<name> [<prefix>]]), connect, and act."""
    LOG.append(Path(sys.argv[1]))
    args = sys.argv[2:]
    command, name, prefix = [*args, None, None, None][:3]
    name = name or "all"
    if (
        command not in ("save", "restore")
        or len(args) > MAX_ARGS
        or (command == "restore" and prefix)
    ):
        log(f"ERROR: {USAGE}")
        sys.exit(1)
    if not re.fullmatch(r"[\w.-]+", name, re.ASCII):
        log(f"ERROR: name {name!r}: use letters, digits, '.', '_', '-'")
        sys.exit(1)

    # An ArrangementError is a finding about the windows or the file, said
    # in one line; anything else is a bug and keeps its traceback (the
    # package prints it and exits 1). Caught in here, as the package catches
    # every Exception that leaves `run`.
    async def act(connection: iterm2.Connection) -> None:
        app = await iterm2.async_get_app(connection)
        if app is None:
            msg = "iTerm2's Python API returned no app"
            raise ArrangementError(msg)
        if command == "save":
            await save(app, name, prefix)
        else:
            await restore(connection, name)

    async def run(connection: iterm2.Connection) -> None:
        try:
            await act(connection)
        except ArrangementError as e:
            log(f"ERROR: {e}")
            sys.exit(1)

    iterm2.run_until_complete(run)


if __name__ == "__main__":
    main()

# /// script
# requires-python = ">=3.11"
# dependencies = ["iterm2==2.25"]
# ///
"""What runs on iTerm2's Python API while iTerm2 runs: bell banners and Cmd-T.

Run by iterm2_api.lua (hs.task, `uv run --script`) for as long as iTerm2
runs, one connection for both jobs:

    iTerm2 (Python API)                          this script
      bellCount of a session rises  -------->  on screen? (tab selected in the
      (VariableMonitor per session)            key window, iTerm2 active)
                                                 yes -> nothing
                                                 no  -> "bell", session pending
      focus change (app, window, tab) ------>  each pending session now on
                                               screen -> "seen"
      session ends  ------------------------>  was pending -> "gone"
      Cmd-T (the Dotfiles profile binds it   -> ssh_new_tab: a key repeat
      to ssh_new_tab(session_id: id))           (KeyRepeats)? -> nothing;
                                                else the session's foreground
                                                job ssh, its login replayable
                                                (ssh_command.py)?
                                                  yes -> a new tab in that
                                                         window types the login
                                                  no  -> iTerm2's own New Tab
      connection closes (iTerm2 quit) ------>  exit

    stdout, one JSON object per line, to Hammerspoon:
      {"event": "ready", "sessions": 11}
      {"event": "bell", "session": "<id>", "name": "fish:~", "tab": 2,
       "window": "~/.dotfiles"}
      {"event": "seen", "session": "<id>"}     also "gone"
    stdin, one command per line, from Hammerspoon:
      activate <id>      a banner was clicked: bring that session to front

Bells: pending is "rang since its tab was last in view". Every bell of a
pending session is sent: whether its banner is still up, or was dismissed by
hand (alt+0, its close button) and needs a new one, only Hammerspoon can
tell. On screen means the tab, not the pane: every pane of the selected tab
is in view.

Cmd-T: while this script is not running, iTerm2 finds no ssh_new_tab and
Cmd-T does nothing (the error is only in iTerm2's Script Console); its end
is reported by Hammerspoon, which starts it again, see iterm2_api.lua. A
held Cmd-T opens one tab: iTerm2 calls ssh_new_tab on each autorepeat too,
and KeyRepeats drops those.

A session that ends while it is handled is no error: it is gone. Log lines
go to stderr, UTC-stamped, and Hammerspoon writes them to its event log.
Any other error ends the script with a traceback (the iterm2 package exits
1), which Hammerspoon reports and follows by starting it again unless
iTerm2 has just quit, as does the connection closing; stdin closing
(Hammerspoon reloaded or quit) ends it with 0.
"""

import asyncio
import ctypes
import json
import sys
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime

import iterm2
import iterm2.notifications
import iterm2.rpc
import ssh_command

# Seconds to keep trying to register ssh_new_tab while the previous run
# still holds it: after a Hammerspoon reload the new run starts before the
# old one has seen its stdin close (iTerm2 then refuses with
# DUPLICATE_SERVER_ORIGINATED_RPC).
REGISTER_WAIT = 5.0


def log(msg: str) -> None:
    """One UTC-stamped line on stderr, which Hammerspoon logs."""
    stamp = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%S.%fZ}"
    print(stamp, msg, file=sys.stderr, flush=True)  # noqa: T201


def emit(event: str, **fields: object) -> None:
    """One event line on stdout for Hammerspoon."""
    print(json.dumps({"event": event, **fields}), flush=True)  # noqa: T201


# What the API raises about a session (or its window) that has gone, e.g.
#   RPCException("SESSION_NOT_FOUND")             reading one of its variables
#   SubscriptionException("INVALID_IDENTIFIER")   subscribing to one
# (checked against iTerm2 3.7.4 with a made-up session id).
GONE = {"SESSION_NOT_FOUND", "WINDOW_NOT_FOUND", "TAB_NOT_FOUND", "INVALID_IDENTIFIER"}


def is_gone(error: Exception) -> bool:
    """Tell whether an API error says its session, window or tab is gone."""
    api_errors = (iterm2.rpc.RPCException, iterm2.notifications.SubscriptionException)
    return isinstance(error, api_errors) and str(error) in GONE


def short(session_id: str) -> str:
    """Shorten a session id to 8 characters, enough to tell sessions apart in a log."""
    return session_id[:8]


# --- bells -------------------------------------------------------------------


class Bells:
    """Which sessions rang since their tab was last in view, and their bell counts."""

    def __init__(self, app: iterm2.App) -> None:
        """Track `app`, whose windows, tabs and focus the package keeps current."""
        self.app = app
        self.pending: set[str] = set()  # session ids rung since last in view

    def on_screen(self, session_id: str) -> bool:
        """Tell whether the session's tab is in view: iTerm2 in front, tab selected."""
        window = self.app.current_window
        if not self.app.app_active or window is None or window.current_tab is None:
            return False
        return any(s.session_id == session_id for s in window.current_tab.all_sessions)

    async def rang(self, session: iterm2.Session) -> None:
        """Send a bell in `session` to Hammerspoon, unless its tab is in view."""
        sid = session.session_id

        # The common bell, in the tab in view (Claude Code's Stop bell in the
        # active tab), needs no reads: settled before the awaits below.
        if self.on_screen(sid):
            log(f"bell in {short(sid)}: on screen, no banner")
            return

        # What the banner names: the session as it is now, its tab's place in
        # the window (iTerm2's "#<n>"), and the window's own title. A buried
        # session (Session > Bury) is in no window: nothing to show or visit.
        window, tab = self.app.get_window_and_tab_for_session(session)
        if window is None or tab is None:
            log(f"bell in {short(sid)}: in no window (buried or closing), no banner")
            return
        try:
            name = await session.async_get_variable("name")
            title = await window.async_get_variable("titleOverride")
        except Exception as e:
            if not is_gone(e):
                raise
            log(f"bell in {short(sid)}: its session went away ({e}), no banner")
            return
        number = window.tabs.index(tab) + 1

        # Checked again, the reads above having awaited: no await from here
        # on, so the check and the event are one step and a focus change
        # cannot slip in between and miss this bell.
        if self.on_screen(sid):
            log(f"bell in {short(sid)}: came on screen while read, no banner")
            return
        self.pending.add(sid)
        log(f"bell in {short(sid)} ({name!r}, tab #{number}, window {title!r}): sent")
        emit("bell", session=sid, name=name, tab=number, window=title)

    def focus_changed(self) -> None:
        """After a focus change: each pending session now on screen has been seen.

        The app's focus is current by then: iterm2.App subscribed to focus
        changes before FocusMonitor did, and the package runs a notification's
        handlers in that order, each to its end.
        """
        for sid in sorted(self.pending):
            if self.on_screen(sid):
                self.pending.discard(sid)
                log(f"{short(sid)} on screen: banner closes")
                emit("seen", session=sid)

    def ended(self, session_id: str) -> None:
        """Close the banner of a session that ended: it has nothing left to show."""
        if session_id in self.pending:
            self.pending.discard(session_id)
            log(f"{short(session_id)} ended: banner closes")
            emit("gone", session=session_id)


async def watch_session(
    connection: iterm2.Connection,
    bells: Bells,
    session_id: str,
) -> None:
    """Report each rise of one session's bellCount; cancelled when the session ends."""
    session = bells.app.get_session_by_id(session_id)
    if session is None:
        log(f"{short(session_id)} ended before it could be watched")
        return

    async def bell_count() -> int:
        # Unset until the session's first bell, i.e. 0.
        return int(await session.async_get_variable("bellCount") or 0)

    # Read before and after subscribing, so a bell between the two is a bell:
    #   before 0, subscribe, bell (update 1 queued), read 1 -> rang; the
    #   queued update then reads 1 -> 1, no bell
    # Reading only after would take that 1 for the starting count and miss
    # it. bellCount only counts up; anything else is logged, never taken for
    # a bell. A session that ends between its arrival and here (a split
    # that exits at once) fails the subscription or a read: it is done, not
    # an error.
    try:
        before = await bell_count()
        async with iterm2.VariableMonitor(
            connection,
            iterm2.VariableScopes.SESSION,
            "bellCount",
            session_id,
        ) as mon:
            count = await bell_count()
            if count > before:
                await bells.rang(session)
            while True:
                before, count = count, int(await mon.async_get() or 0)
                if count > before:
                    await bells.rang(session)
                else:
                    log(
                        f"{short(session_id)}: bellCount {before} -> {count}, no bell",
                    )
    except Exception as e:
        if not is_gone(e):
            raise
        log(f"{short(session_id)} went away while watched ({e})")


async def watch_focus(connection: iterm2.Connection, bells: Bells) -> None:
    """Close banners as their tabs come into view."""
    async with iterm2.FocusMonitor(connection) as mon:
        while True:
            await mon.async_get_next_update()
            bells.focus_changed()


async def watch_sessions(
    connection: iterm2.Connection,
    bells: Bells,
    failed: asyncio.Future[None],
) -> None:
    """Run a watch_session task per session, now and later, until each one ends."""
    tasks: dict[str, asyncio.Task[None]] = {}

    # A task that dies of an error ends the script through `failed`; one
    # cancelled because its session ended is expected.
    def finished(task: asyncio.Task[None]) -> None:
        error = None if task.cancelled() else task.exception()
        if error is not None and not failed.done():
            failed.set_exception(error)

    async def terminations() -> None:
        async with iterm2.SessionTerminationMonitor(connection) as mon:
            while True:
                sid = await mon.async_get()
                task = tasks.pop(sid, None)
                if task:
                    task.cancel()
                bells.ended(sid)

    ends = asyncio.create_task(terminations())
    ends.add_done_callback(finished)
    async with iterm2.EachSessionOnceMonitor(bells.app) as mon:
        while True:
            sid = await mon.async_get()
            task = asyncio.create_task(watch_session(connection, bells, sid))
            task.add_done_callback(finished)
            tasks[sid] = task


# --- Cmd-T -------------------------------------------------------------------


def key_repeat_delay() -> float:
    """Return macOS's delay before a held key repeats, in seconds.

    NSEvent.keyRepeatDelay (System Settings > Keyboard > Delay until
    repeat), the value AppKit applies, through the Objective-C runtime: the
    InitialKeyRepeat default it derives from is unset on a machine that never
    moved the slider (25 there reads as 0.417 s, not 25 x 15 ms).
    """
    objc = ctypes.CDLL("/usr/lib/libobjc.dylib")
    ctypes.CDLL("/System/Library/Frameworks/AppKit.framework/AppKit")
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    send = ctypes.CFUNCTYPE(ctypes.c_double, ctypes.c_void_p, ctypes.c_void_p)(
        ("objc_msgSend", objc),
    )
    ns_event = objc.objc_getClass(b"NSEvent")
    if not ns_event:
        msg = "AppKit loaded, but the Objective-C runtime has no NSEvent class"
        raise RuntimeError(msg)
    delay = send(ns_event, objc.sel_registerName(b"keyRepeatDelay"))
    if not 0 < delay < KeyRepeats.MAX_DELAY:
        msg = (
            f"NSEvent.keyRepeatDelay is {delay} s, outside (0, {KeyRepeats.MAX_DELAY})"
        )
        raise RuntimeError(msg)
    return delay


class KeyRepeats:
    """Tells a held Cmd-T's autorepeats from presses.

    iTerm2 runs a key binding on every key down, autorepeats included, and
    the call carries no sign of which it was. A held key repeats `delay`
    after the press, then every KeyRepeat interval (33 ms by default), so a
    call sooner than `delay` + SLACK after the previous call, a press or a
    repeat, is a repeat. With delay 0.417:

        press   t=0.000  -> taken
        repeat  t=0.417  -> dropped (0.417 after the last call)
        repeat  t=0.450  -> dropped, and on while the key is held
        press   t=2.000  -> taken

    The cost: a deliberate second Cmd-T sooner than that is dropped too.
    """

    SLACK = 0.15  # seconds of jitter in when a repeat reaches this script
    MAX_DELAY = 5.0  # seconds; the slider's longest is about 2

    def __init__(self, delay: float) -> None:
        """Take calls closer than `delay` + SLACK for repeats."""
        self.gap = delay + self.SLACK
        self.last: float | None = None  # when the last call came, taken or not

    def repeat(self, now: float) -> bool:
        """Tell whether a call at `now` (seconds, monotonic) is a repeat."""
        last, self.last = self.last, now
        return last is not None and now - last < self.gap


async def cmd_t(
    app: iterm2.App,
    session_id: str,
    plain_new_tab: Callable[[], Awaitable[None]],
) -> None:
    """Cmd-T pressed in `session_id`: a new tab on the same machine, if ssh'd.

    The test is the local foreground job (jobName, commandLine), the process
    iTerm2's own pty sees, so it holds whatever runs on the far side (a
    remote tmux, a nested ssh: that one reopens the first hop). Only the
    login is replayed, `ssh <options> <destination>` from ssh_command.py: a
    remote command (`ssh vm ./deploy.sh`), a forward or -N never runs twice,
    and a command line it cannot re-parse safely gets iTerm2's plain New Tab
    (`plain_new_tab`) instead, as does any tab not running ssh.

    The new tab goes through the shell, not a tab "command", so exiting ssh
    leaves a local shell, as if the login had been typed by hand. It uses
    the default profile, as iTerm2's New Tab does, in the window the key was
    pressed in. ControlMaster in ~/.ssh/config makes the second connection
    instant.
    """
    session = app.get_session_by_id(session_id)
    if session is None:
        log(f"Cmd-T in {short(session_id)}: session gone, nothing to do")
        return
    try:
        job = await session.async_get_variable("jobName")
        command = await session.async_get_variable("commandLine")
    except Exception as e:
        if not is_gone(e):
            raise
        log(f"Cmd-T in {short(session_id)}: session went away ({e}), nothing to do")
        return

    # Both are set for every live session (a fresh tab reports its shell);
    # missing means iTerm2 renamed or dropped them, which would otherwise
    # read as "not ssh" and silently turn the feature off. The test is
    # jobName, the process name, so `/usr/bin/ssh vm` counts too.
    if not isinstance(job, str) or not isinstance(command, str):
        msg = (
            f"jobName {job!r} / commandLine {command!r} of {session_id} are not strings"
        )
        raise TypeError(msg)
    if job != "ssh":
        log(f"Cmd-T in {short(session_id)}: foreground job {job}, New Tab")
        await plain_new_tab()
        return

    # The log gets the replay only, never the dropped remote command, which
    # may carry a secret (`ssh vm env TOKEN=... ./job`).
    try:
        login = ssh_command.interactive(command)
    except ssh_command.NotReplayableError as e:
        log(f"Cmd-T in {short(session_id)}: ssh line not replayable ({e}), New Tab")
        await plain_new_tab()
        return
    window, _ = app.get_window_and_tab_for_session(session)
    if window is None:
        msg = f"session {session_id} had keyboard focus but is in no window"
        raise RuntimeError(msg)
    tab = await window.async_create_tab()
    if tab is None or tab.current_session is None:
        msg = f"iTerm2 made no new tab in window {window.window_id}"
        raise RuntimeError(msg)
    await tab.current_session.async_send_text(login + "\n")
    log(f"Cmd-T in {short(session_id)}: `{login}` in a new tab of {window.window_id}")


async def register_cmd_t(
    connection: iterm2.Connection,
    app: iterm2.App,
    failed: asyncio.Future[None],
) -> None:
    """Register ssh_new_tab, the function the Dotfiles profile binds Cmd-T to."""
    loop = asyncio.get_running_loop()
    repeats = KeyRepeats(key_repeat_delay())
    log(f"Cmd-T: a call within {repeats.gap:.3f} s of the last is a key repeat")

    # iTerm2's own Shell > New Tab, as the key would have run without the
    # binding: the default profile, and its directory rules.
    new_tab = iterm2.MainMenu.Shell.NEW_TAB.value.identifier
    if new_tab is None:
        msg = "the iterm2 package names no menu id for Shell > New Tab"
        raise RuntimeError(msg)

    async def plain_new_tab() -> None:
        await iterm2.MainMenu.async_select_menu_item(connection, new_tab)

    # An error here would otherwise only reach iTerm2's Script Console (the
    # package returns it to iTerm2 and carries on): it ends the script, and
    # Hammerspoon reports it. The Reference default is the package's way to
    # name the variable whose value (the focused session's id, a str)
    # iTerm2 passes in.
    @iterm2.RPC
    async def ssh_new_tab(
        session_id: str = iterm2.Reference("id"),  # ty: ignore[invalid-parameter-default]
    ) -> None:
        if repeats.repeat(loop.time()):
            log(f"Cmd-T in {short(session_id)}: a key repeat, ignored")
            return
        try:
            await cmd_t(app, session_id, plain_new_tab)
        except Exception as e:
            if not failed.done():
                failed.set_exception(e)
            raise

    await register(connection, ssh_new_tab.async_register)
    log("ssh_new_tab registered (Cmd-T)")


async def register(
    connection: iterm2.Connection,
    async_register: Callable[[iterm2.Connection], Awaitable[object]],
) -> None:
    """Register ssh_new_tab, waiting up to REGISTER_WAIT for the last run to free it."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + REGISTER_WAIT
    while True:
        try:
            await async_register(connection)
        except iterm2.notifications.SubscriptionException as e:  # noqa: PERF203 - a bounded retry
            if str(e) != "DUPLICATE_SERVER_ORIGINATED_RPC" or loop.time() > deadline:
                raise
            log("ssh_new_tab is still the previous run's; waiting for it to exit")
            await asyncio.sleep(0.2)
        else:
            return


# --- the script ----------------------------------------------------------------


async def read_commands(bells: Bells) -> None:
    """Commands from Hammerspoon on stdin, until it closes."""
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(
        lambda: asyncio.StreamReaderProtocol(reader),
        sys.stdin,
    )
    while line := (await reader.readline()).decode():
        verb, _, sid = line.strip().partition(" ")
        if verb != "activate" or not sid:
            msg = f"unknown command from Hammerspoon: {line!r}"
            raise ValueError(msg)
        session = bells.app.get_session_by_id(sid)
        if session is None:
            log(f"activate {short(sid)}: session gone")
            continue
        try:
            await session.async_activate(select_tab=True, order_window_front=True)
        except Exception as e:
            if not is_gone(e):
                raise
            log(f"activate {short(sid)}: session went away ({e})")
            continue
        await bells.app.async_activate(raise_all_windows=False)
        log(f"activate {short(sid)}: brought to front")
    log("stdin closed (Hammerspoon reloaded or quit): exiting")


async def main(connection: iterm2.Connection) -> None:
    """Serve bells and Cmd-T until stdin closes or something fails."""
    app = await iterm2.async_get_app(connection)
    if app is None:
        msg = "iTerm2's Python API returned no app"
        raise RuntimeError(msg)
    bells = Bells(app)
    failed: asyncio.Future[None] = asyncio.get_running_loop().create_future()

    # The package reads the connection in a task of its own, and when iTerm2
    # quits that task dies with the error alone: the monitors above would
    # wait on their queues forever, and the script with them.
    async def closed() -> None:
        websocket = connection.websocket
        if websocket is None:
            msg = "connected, but the iterm2 package holds no websocket"
            raise RuntimeError(msg)
        await websocket.wait_closed()
        msg = "iTerm2 closed the connection (it quit, or its API server stopped)"
        raise ConnectionError(msg)

    # Run until the first of: stdin closes (normal end), the connection
    # closes, a watcher fails, or a session task or Cmd-T fails (through
    # `failed`). Exceptions propagate, and the package turns them into a
    # traceback and exit 1.
    workers = [
        asyncio.create_task(read_commands(bells)),
        asyncio.create_task(closed()),
        asyncio.create_task(watch_focus(connection, bells)),
        asyncio.create_task(watch_sessions(connection, bells, failed)),
        failed,
    ]
    await register_cmd_t(connection, app, failed)
    sessions = sum(len(t.all_sessions) for w in app.windows for t in w.tabs)
    log(f"connected: {sessions} session(s)")
    emit("ready", sessions=sessions)
    done, rest = await asyncio.wait(workers, return_when=asyncio.FIRST_COMPLETED)
    for task in rest:
        task.cancel()
    for task in done:
        task.result()


# retry: iTerm2 starts its API server a moment after it launches, and this
# runs from its launch. Hammerspoon bounds the wait (READY_TIMEOUT there).
# Guarded so scripts/tests/iterm2_api_test.py can import it.
if __name__ == "__main__":
    log("connecting to iTerm2's Python API")
    iterm2.run_until_complete(main, retry=True)

#!/usr/bin/env python3
r"""tmux history: prefix C-s takes a session back to the window it last stayed in.

Back to the window of the session that it left most recently after showing
it for a second or more. A window passed through on the way somewhere
(Cmd-J, Cmd-K held down) is a stay of a fraction of a second, and does not
count; neither does a window closed since. A session's history is its own:
prefix C-s never leaves the session, and two terminals showing one session
share it, as they share its current window.

    tmux server (the default socket, or -L <name>)
      |  at start, tmux.conf runs, for a server in tmux's own socket folder:
      |    run-shell -b "exec ~/.dotfiles/scripts/tmux_history.py run -S <socket>"
      |  one control-mode client in a session of its own, "tmux-history",
      |  which tmux removes when the client goes (destroy-unattached):
      |    tmux -N -C new-session -s tmux-history -f ignore-size,no-output
      v
    run: the tracker, one per server, for the server's life
      |  %session-window-changed $3 @4: a session's window changed, told
      |    the moment it happens, for every session
      |  list-sessions: where each session stands, at connect and on
      |    %sessions-changed; tmux-history alone in it: the last session
      |  %window-close, %unlinked-window-close: its stays are dropped
      v
    stays, per session, in memory: (window, arrived, left)
      ^
      |  prefix C-s (tmux.conf):
      |    set-buffer -b tmux-history-ask '/dev/pts/3 $3:@4'
      |  tmux tells every control client at once: %paste-buffer-changed
      |  tmux-history-ask; the tracker reads the buffer, deletes it, and
      |  answers: select-window -t '$3:@1', or a message to /dev/pts/3
      v
    events.log: ~/.dotfiles/.logs/<UTC>_tmux_history/events.log, a line per
    window change and per key press

Why a buffer: the key has to reach a running process without starting one
(a Python start is 60 ms or more), and a buffer is the one thing a binding
can set that tmux both reports to a control client at once (0.4 ms,
measured) and repaints no terminal for. An option tells no control client,
and setting one, any one, redraws every terminal of the server.

    tmux.conf's binding checks first that session tmux-history exists,
    which it does exactly while a tracker is connected: without one, the
    key says so instead of leaving a buffer nobody reads.

A session's stays, from the windows it shows:

    t        window
    10:00    @1       stay @1 10:00 - 10:30
    10:30    @2       (0.4 s: passed through, not kept)
    10:30.4  @3       the stay still going
    prefix C-s at @3 -> @1; @2 was passed through

One tracker per server, for the server's life:

    server starts        -> tmux.conf starts the tracker; a second one
                            (tmux.conf sourced again) finds tmux-history
                            there ("duplicate session") and exits at once
    tmux-history killed  -> tmux detaches the client (%exit); it reconnects,
                            which makes tmux-history again
    sessions down to 1   -> the last is its own: it leaves, tmux removes the
                            session, and exit-empty (tmux.conf) ends the server
    tracker killed (-9)  -> its client goes, and tmux-history with it
    server exits         -> tmux sends its jobs SIGTERM: exit 0
    SIGHUP               -> it runs itself again, on the code now on disk
                            (scripts/update.sh sends it); the stays so far
                            are forgotten
    something unexpected -> exit 1, the reason on stdout, which tmux shows
                            in a pane, and in events.log

It writes nothing to stdout otherwise: tmux shows a job's output when the
job ends, so every line would land on screen.

Why a session of its own: a control client counts as attached to its session
and reports itself focused, which would hide that session from
focus-out-unattached.sh (Claude's synthetic focus-out) and tmux_switch_session.sh,
and could look like a watcher to ntfy-stop.sh. In "tmux-history" it disturbs
nothing; prefix s and prefix w leave it out. The session lives exactly as
long as the connection, however the connection ends: that is what lets it
stand for a running tracker, to tmux.conf's binding and to a second tracker.
It is never left alone, or exit-empty could never end the server, and the
next start would not read the login environment afresh.
"""

# A script invoked by path, no license header, as in scripts/.
# ruff: noqa: CPY001

import argparse
import os
import re
import signal
import subprocess
import sys
import time
from collections import deque
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from pathlib import Path
from types import FrameType

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from event_log import EventLog

SESSION = "tmux-history"
ASK = "tmux-history-ask"  # the buffer prefix C-s sets
# How long a session must have shown a window for prefix C-s to go back to
# it: less is a window passed through.
LEAST = 1.0
# The stays kept per session, newest last: far more than a key press ever
# goes back past (only windows closed since).
KEPT = 200

# Sent with the attach, in the same command list, so no moment passes in
# which the session could outlive its client: tmux removes it when its last
# client detaches, or dies (kill -9 included).
OWN = f"set-option -t ={SESSION}: destroy-unattached on"
# Each session's current window, one line per session: "$3 @4".
# %session-window-changed tells of each switch the moment it happens, but
# not where a session stands that was there before the tracker, or is new.
LIST = "list-sessions -F '#{session_id} #{window_id}'"
# A window closed: "%window-close @9" for one of the tracker's own session,
# "%unlinked-window-close @9" for any other.
CLOSES = {"%window-close", "%unlinked-window-close"}
# What tmux -N prints when no server listens on the socket. As in
# tmux_arrangement.py, whose import would pull in ssh_command for one line.
NO_SERVER = re.compile(r"no server running|error connecting to")


class TrackerError(Exception):
    """Something the tracker cannot go on from; the message says what."""


class Stop(Exception):  # noqa: N818 - a signal, not an error
    """A signal asked the tracker to stop."""


class Tracked(Exception):  # noqa: N818 - an answer, not an error
    """Session tmux-history exists already: another tracker's."""


@dataclass(frozen=True)
class Stay:
    """A stretch in which a session (the one whose stays hold it) showed one window."""

    window_id: str
    start: float
    end: float


@dataclass(frozen=True)
class Reply:
    """What a command printed, the lines between %begin and %end; ok: not %error."""

    lines: tuple[str, ...]
    ok: bool = True


@dataclass(frozen=True)
class End:
    """Why one connection ended, and whether to connect again."""

    reason: str
    again: bool


def parse_listed(line: str) -> tuple[str, str]:
    """Return session and window from a line LIST prints: "$3 @4" -> ("$3", "@4").

    Another shape raises: LIST's format and this disagree.
    """
    m = re.fullmatch(r"(\$\d+) (@\d+)", line)
    if not m:
        msg = f"{LIST} printed {line!r}, not '$<session> @<window>'"
        raise TrackerError(msg)
    return m[1], m[2]


def parse_ask(text: str) -> tuple[str, str, str]:
    """Return client, session and window from the buffer prefix C-s sets.

    "/dev/pts/3 $3:@4" -> ("/dev/pts/3", "$3", "@4"). Another shape raises:
    tmux.conf's binding and this disagree.
    """
    m = re.fullmatch(r"(\S+) (\$\d+):(@\d+)", text)
    if not m:
        msg = f"{ASK} holds {text!r}, not '<client> $<session>:@<window>' (tmux.conf)"
        raise TrackerError(msg)
    return m[1], m[2], m[3]


@dataclass
class Pending:
    """A command sent to tmux, waiting for its reply.

    kind      the reply                    on %error
    quiet     nothing printed              raise: the tracker's own command failed
    sessions  LIST's lines                 raise
    ask       the buffer's text            log: a second press read it already
    answer    nothing printed              log: the switch or message did not land
    """

    kind: str
    command: str
    note: str = ""  # ask, answer: what the log line says it did


@dataclass
class Tracker:
    """One connection's view: each session's window and stays; answers prefix C-s.

        the attach's reply (tmux's first) -> connected; LIST sent; refused
                                            as "duplicate session": Tracked
        LIST's reply                     -> where each session stands; the
                                            stays of sessions gone dropped;
                                            only tmux-history: leave
        %session-window-changed $1 @4    -> $1's stay before ends, one in
                                            @4 begins
        %sessions-changed                -> LIST again
        %window-close @9                 -> the stays in @9 dropped
        %paste-buffer-changed <ASK>      -> show-buffer, delete-buffer;
          the reply: a client and where     select-window, or a message
          it is

    Commands are answered in the order they are sent: `pending` holds what
    each reply is for.
    """

    log: EventLog
    send: Callable[[str], None]
    connected: bool = False
    pending: deque[Pending] = field(default_factory=deque)
    # Each session's current window, and since when: {"$3": ("@4", t)}.
    current: dict[str, tuple[str, float]] = field(default_factory=dict)
    stays: dict[str, deque[Stay]] = field(default_factory=dict)

    def command(self, p: Pending) -> None:
        """Send a command, and note what its reply is for."""
        self.pending.append(p)
        self.send(p.command)

    def connect(self, attach: str | Reply) -> None:
        """Take tmux's reply to the attach; then ask where the sessions stand.

        A second tracker's attach finds the session there: Tracked. OWN came
        in the attach's command list, so its reply is the next one.
        """
        if not isinstance(attach, Reply):
            msg = f"tmux's first line is {attach!r}, not the reply to the attach"
            raise TrackerError(msg)
        error = " | ".join(attach.lines)
        if error == f"duplicate session: {SESSION}":
            msg = f"tracked already: session {SESSION} exists"
            raise Tracked(msg)
        if not attach.ok:
            msg = f"tmux refused the attach: {error}"
            raise TrackerError(msg)
        self.connected = True
        self.log.note(f"connected: control client in session {SESSION}")
        self.pending.append(Pending("quiet", OWN))
        self.command(Pending("sessions", LIST))

    def handle(self, line: str | Reply) -> End | None:
        """Act on one notification or reply; return how the connection ends, if so."""
        if isinstance(line, Reply):
            return self.answered(line)
        kind, _, rest = line.partition(" ")
        if kind == "%exit":
            # The server exiting (then a SIGTERM follows), or the client
            # detached by hand: connecting again tells which.
            return End(f"tmux sent %exit {rest}".strip(), again=True)
        if kind == "%session-changed" and rest.split(" ", 1)[1:] != [SESSION]:
            # Moved to another session by hand (switch-client), where it
            # would count as attached: start over in a new one.
            return End(f"moved out of {SESSION} to {rest}", again=True)
        self.record(kind, rest)
        return None

    def record(self, kind: str, rest: str) -> None:
        """Act on what the notification `kind`, with `rest` after it, reports."""
        if kind == "%session-window-changed":
            self.window_changed(*parse_listed(rest), time.time())
        elif kind == "%sessions-changed":
            self.command(Pending("sessions", LIST))
        elif kind in CLOSES:
            self.closed(rest)
        elif kind == "%paste-buffer-changed" and rest == ASK:
            self.command(Pending("ask", f"show-buffer -b {ASK}", note="read the ask"))
            self.command(Pending("quiet", f"delete-buffer -b {ASK}"))

    def answered(self, reply: Reply) -> End | None:
        """Act on the reply to the oldest command still waiting for one.

        Return how the connection ends, when the list shows it is time.
        """
        if not self.pending:
            msg = f"a command reply the tracker did not ask for: {reply.lines!r}"
            raise TrackerError(msg)
        p = self.pending.popleft()
        if not reply.ok:
            error = " | ".join(reply.lines)
            if p.kind in {"quiet", "sessions"}:
                msg = f"tmux refused a tracker command: {p.command}: {error}"
                raise TrackerError(msg)
            self.log.note(f"FAILED to {p.note}: {p.command}: {error}")
            return None
        if p.kind == "sessions":
            return self.sessions_listed(reply.lines, time.time())
        if p.kind == "ask":
            self.answer(*parse_ask("\n".join(reply.lines)))
        elif p.kind == "answer":
            self.log.note(p.note)
        elif reply.lines:
            msg = f"{p.command} printed {reply.lines!r}; the tracker expects nothing"
            raise TrackerError(msg)
        return None

    def sessions_listed(self, lines: tuple[str, ...], t: float) -> End | None:
        """Take where each session stands at `t`; forget the sessions gone.

        A session known already carries on: its switches came as
        notifications. One showing another window than the tracker thought
        switched while the list was on its way, before its notification.
        The tracker's own session alone on the list: the End, for good.
        """
        listed = dict(map(parse_listed, lines))
        if len(listed) == 1:
            # The first session is made before tmux.conf's run-shell job
            # gets here, so 1 is never "not yet": it is "no more".
            reason = f"{SESSION} is the last session; leaving, so the server exits"
            return End(reason, again=False)
        for session, window in listed.items():
            self.window_changed(session, window, t)
        for session in self.current.keys() - listed.keys():
            del self.current[session]
            self.stays.pop(session, None)
            self.log.note(f"{session} gone")
        return None

    def window_changed(self, session: str, window: str, t: float) -> None:
        """Note that `session` shows `window` from `t`: its stay before ends.

        $1 at @1 since 10:00:00, at @2 from 10:00:30  ->  stay @1, 30 s
        $1 at @2 since 10:00:30, at @3 from 10:00:30.4 ->  no stay: 0.4 s
        """
        before = self.current.get(session)
        if before is not None and before[0] == window:
            return
        if before is not None and t - before[1] >= LEAST:
            stays = self.stays.setdefault(session, deque(maxlen=KEPT))
            stays.append(Stay(before[0], before[1], t))
        self.current[session] = (window, t)
        self.log.note(f"{session} at {window}")

    def closed(self, window: str) -> None:
        """Drop every stay in a window that closed: there is no going back to it."""
        for session, stays in self.stays.items():
            if any(s.window_id == window for s in stays):
                self.stays[session] = deque(
                    (s for s in stays if s.window_id != window),
                    KEPT,
                )

    def answer(self, client: str, session: str, window: str) -> None:
        """Take `session`, at `window`, back to its last stay elsewhere.

        `client` pressed the key, and is told when there is nowhere to go.

            stays of $1: @1, @2, @4 (left last); at @4 -> @2; at @2 -> @4
        """
        now = time.time()
        here = f"{client} at {session}:{window}"
        stay = next(
            (s for s in reversed(self.stays.get(session, ())) if s.window_id != window),
            None,
        )
        if stay is None:
            text = "no other window of this session to go back to"
            command = f"display-message -c '{client}' 'tmux history: {text}'"
            self.command(Pending("answer", command, note=f"{here}: {text}"))
            return
        target = f"{session}:{stay.window_id}"
        ago, stayed = now - stay.end, stay.end - stay.start
        note = f"{here}: to {target}, left {ago:.1f}s ago after {stayed:.1f}s"
        command = f"select-window -t '{target}'"
        self.command(Pending("answer", command, note=note))


def read_notifications(lines: Iterator[str]) -> Iterator[str | Reply]:
    """Yield the notification lines, and each command's reply, %error ones too.

    The first is the attach's: tmux answers it before any notification.
    """
    for line in lines:
        if not line.startswith("%begin "):
            yield line
            continue
        body, ok = [], True
        for inner in lines:
            if inner.startswith(("%end ", "%error ")):
                ok = inner.startswith("%end ")
                break
            body.append(inner)
        yield Reply(tuple(body), ok)


def control_lines(tmux: list[str]) -> tuple[subprocess.Popen[str], Iterator[str]]:
    """Start the control client in SESSION; return it and its stdout lines."""
    argv = [
        *tmux,
        "-N",
        "-C",
        "new-session",
        "-s",
        SESSION,
        "-c",
        "/",
        "-f",
        # Not read-only, though the tracker never types. A command run
        # outside tmux (a script's `tmux send-keys -t ...`) acts for the
        # server's latest client; with no terminal attached that is this one,
        # and for a read-only client tmux refuses send-keys: "client is
        # read-only". The manager's start at boot typed no `claude` that way.
        "ignore-size,no-output",
        "tail -f /dev/null",
        ";",
        *OWN.split(" "),
    ]
    # Run from inside tmux (a test, a manual run), tmux would refuse to
    # attach: "sessions should be nested with care, unset $TMUX to force".
    env = {k: v for k, v in os.environ.items() if k != "TMUX"}
    proc = subprocess.Popen(  # noqa: S603 - tmux with fixed arguments
        argv,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    if proc.stdout is None or proc.stdin is None:
        msg = "tmux control client started without pipes"
        raise TrackerError(msg)
    return proc, (line.rstrip("\n") for line in proc.stdout)


def send(proc: subprocess.Popen[str], command: str) -> None:
    """Send one command line to the control client."""
    if proc.stdin is None:
        msg = "tmux control client has no stdin"
        raise TrackerError(msg)
    proc.stdin.write(command + "\n")
    proc.stdin.flush()


def run(tmux: list[str], log: EventLog) -> str:
    """Watch one server until it ends; return the signal that stopped it, if any.

    A connection that ends while the server lives (its session killed, its
    client detached) is made again; one that finds no server, or leaves the
    server to exit-empty, ends the run.
    """

    def stop(signum: int, _frame: FrameType | None) -> None:
        raise Stop(signal.Signals(signum).name)

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, stop)
    try:
        while (end := watch(tmux, log)) is not None:
            if not end.again:
                return ""
        log.note("no tmux server: done")
    except Stop as e:
        log.note(f"stopped by {e}")
        return str(e)
    return ""


def watch(tmux: list[str], log: EventLog) -> End | None:
    """Follow the server over one connection; None if there was no server.

    Why it ends is logged before the cleanup: leaving lets the server exit,
    and its SIGTERM can cut the cleanup short (Stop), return value and all.
    """
    proc, lines = control_lines(tmux)
    tracker = Tracker(log, lambda command: send(proc, command))
    try:
        for line in read_notifications(lines):
            if not tracker.connected:
                tracker.connect(line)
                continue
            if (end := tracker.handle(line)) is not None:
                log.note(f"disconnected: {end.reason}")
                return end
    finally:
        err = close(proc)
    if tracker.connected:
        reason = f"tmux closed the connection ({proc.returncode}) {err.strip()}"
        log.note(f"disconnected: {reason.strip()}")
        return End(reason.strip(), again=True)
    if NO_SERVER.search(err):
        return None
    msg = f"tmux control client exited {proc.returncode} before connecting: {err}"
    raise TrackerError(msg.strip())


def close(proc: subprocess.Popen[str]) -> str:
    """End the control client; return its stderr.

    End of input detaches it, and tmux removes its session (OWN). The
    client may have exited already (%exit); closing its stdin is then a
    no-op too.
    """
    try:
        _, err = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        _, err = proc.communicate()
        err += "\n(the control client did not exit in 5 s of its input closing; killed)"
    return err


def track(socket: str) -> int:
    """Run the tracker for the server on `socket`: `run`, and what wraps it."""
    log = EventLog.start("tmux_history", echo=None)
    log.note(f"tracker {os.getpid()} starting: socket {socket}")
    try:
        stopped_by = run(["tmux", "-S", socket], log)
    except Tracked as e:
        log.note(f"{e}; exiting")
        return 0
    except Exception as e:
        log.note(f"FAILED: {type(e).__name__}: {e}")
        # stdout is what tmux shows of a job that fails; stderr it drops.
        print(f"tmux_history.py: tracking {socket} FAILED: {e} (log: {log.path})")  # noqa: T201
        raise
    if stopped_by == "SIGHUP":
        log.note("running again, on the code now on disk")
        os.execv(sys.argv[0], sys.argv)  # noqa: S606 - this script, as it was run
    return 0


def main(argv: list[str]) -> int:
    """Run the subcommand argv names."""
    p = argparse.ArgumentParser(
        prog="tmux_history.py",
        description=__doc__.split("\n")[0],
    )
    sub = p.add_subparsers(dest="command", required=True)
    r = sub.add_parser(
        "run",
        help="watch one tmux server and answer prefix C-s, until it ends"
        " (tmux.conf runs this)",
    )
    r.add_argument(
        "-S",
        dest="socket",
        required=True,
        help="the server's socket path (tmux.conf passes #{socket_path})",
    )
    args = p.parse_args(argv)
    return track(args.socket)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

"""The event log of a Python program that runs on its own (a daemon, a job).

The repo's rule for those (AGENTS.md), as scripts/lib/event_log.sh is for
shell scripts and home/.hammerspoon/event_log.lua for Hammerspoon:

    log = EventLog.start("tmux_history")
    log.note("connected to /tmp/tmux-1000/default")
    -> ~/.dotfiles/.logs/20261109_174200_tmux_history/events.log
       2026-11-09T17:42:00Z connected to /tmp/tmux-1000/default

One directory per run, named by its UTC start; a second run starting in the
same second gets "_2" after the name, and so on, rather than share the file.
The first log started on a UTC day also prunes the old ones
(scripts/prune_logs.sh, which says what goes), as event_log.sh does, so
nothing has to schedule it. Each line goes to
the file and, unless the caller says otherwise, to stdout (the journal, under
systemd), flushed as written, so both read mid-run. A program whose stdout
someone else shows (a tmux run-shell job: tmux puts it on screen) passes
echo=None.
"""

# A module beside the scripts that import it, no license header, as in scripts/lib.
# ruff: noqa: INP001, CPY001

import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Self, TextIO

ROOT = Path.home() / ".dotfiles/.logs"
PRUNE = Path(__file__).resolve().parent.parent / "prune_logs.sh"


class EventLog:
    """UTC-stamped lines, appended to one run's events.log and echoed to stdout."""

    def __init__(self, file: TextIO, echo: TextIO | None) -> None:
        """Log to an open line-buffered file, echoing each line to `echo`, if any."""
        self.file = file
        self.echo = echo
        self.path = Path(file.name)

    @classmethod
    def start(cls, name: str, echo: TextIO | None = sys.stdout) -> Self:
        """Make this run's directory in ~/.dotfiles/.logs, and open its events.log.

        The old logs are pruned once a UTC day, and a prune that fails
        raises: a log directory that cannot be kept in bounds is a finding.
        """
        now = datetime.now(UTC)
        base = ROOT / f"{now:%Y%m%d_%H%M%S}_{name}"
        base.parent.mkdir(parents=True, exist_ok=True)
        directory, n = base, 1
        while True:
            try:
                directory.mkdir()
                break
            except FileExistsError:
                n += 1
                directory = base.with_name(f"{base.name}_{n}")
        # The day's mark checked here, as event_log.sh does, to spare the
        # prune's process on every start after the first of the day.
        if _pruned_on(ROOT) != f"{now:%Y%m%d}":
            subprocess.run([str(PRUNE)], check=True, stdout=subprocess.DEVNULL)  # noqa: S603 - our own script
        file = (directory / "events.log").open("a", buffering=1, encoding="utf-8")
        return cls(file, echo)

    def note(self, message: str) -> None:
        """Append one UTC-stamped line, and echo it."""
        line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {message}\n"
        self.file.write(line)
        if self.echo is not None:
            self.echo.write(line)
            self.echo.flush()


def _pruned_on(root: Path) -> str:
    """Return the UTC day (YYYYMMDD) prune_logs.sh last ran, "" if never."""
    marker = root / ".pruned"
    return marker.read_text(encoding="utf-8").strip() if marker.exists() else ""

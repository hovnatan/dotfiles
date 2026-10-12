# /// script
# requires-python = ">=3.11"
# dependencies = ["iterm2==2.25"]
# ///
r"""Set iTerm2 window title templates, for iterm2_ssh_arrangement.lua's restore.

AppleScript can read a window's title template (titleOverrideFormat) but not
set it ("Only user variables may be set"); the Python API can. A window is
named by the id of one of its sessions, which AppleScript does give:

    iterm2_set_window_titles.py <session id> <template> [<session id> ...]
    e.g. 08ED8F24-... 'ai-agent \(currentTab.currentSession.name)'

One connection for every window, so iTerm2 asks at most once whether this
script may connect. Needs Settings > General > Magic > Enable Python API
(EnableAPIServer, set by scripts/setup_user_symlinks.sh).
"""

import sys
from datetime import UTC, datetime

import iterm2

USAGE = "usage: iterm2_set_window_titles.py <session id> <template> [...]"


def log(msg: str) -> None:
    """Print one UTC-stamped line, flushed: the caller shows it as it comes."""
    print(f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}", flush=True)  # noqa: T201


async def main(connection: iterm2.Connection) -> None:
    """Set each window's template and read it back."""
    args = sys.argv[1:]
    if not args or len(args) % 2:
        raise SystemExit(USAGE)
    app = await iterm2.async_get_app(connection)
    if app is None:
        msg = "iTerm2's Python API returned no app"
        raise SystemExit(msg)

    # Every title is read back after it is set: a window left with the wrong
    # name is a failure, not a skip.
    for session_id, template in zip(args[::2], args[1::2], strict=True):
        session = app.get_session_by_id(session_id)
        if session is None:
            msg = f"no iTerm2 session {session_id}; was its window closed?"
            raise SystemExit(msg)
        window, _tab = app.get_window_and_tab_for_session(session)
        if window is None:
            msg = f"iTerm2 session {session_id} is in no window"
            raise SystemExit(msg)
        await window.async_set_title(template)
        got = await window.async_get_variable("titleOverrideFormat")
        if got != template:
            msg = (
                f"window {window.window_id}: title template reads back {got!r}, "
                f"want {template!r}"
            )
            raise SystemExit(msg)
        log(f"window {window.window_id}: title template {template!r}")


iterm2.run_until_complete(main)

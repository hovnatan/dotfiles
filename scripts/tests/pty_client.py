r"""A terminal for a tmux test: attach to a session in a pty until tmux goes.

usage: pty_client.py <tmux> <socket> <home> <session>
                     [--keys <fifo>] [--screen <file>]

  --keys    each line written to the fifo is sent to tmux as the bytes it
            spells in Python escapes: \x01s is C-a s, \x1b[I a focus-in
  --screen  what tmux sends the terminal to draw, as it comes
"""

# ruff: noqa: INP001, CPY001

import argparse
import os
import pty
import select


def attach(tmux: str, socket: str, home: str, session: str) -> int:
    """Start tmux attached to the session in a new pty; return the pty."""
    pid, tty = pty.fork()
    if pid == 0:
        env = {"HOME": home, "PATH": "/usr/bin:/bin", "TERM": "xterm-256color"}
        os.execve(tmux, [tmux, "-S", socket, "attach", "-t", "=" + session], env)  # noqa: S606
    return tty


def relay(tty: int, keys: int | None, screen: int | None) -> None:
    """Pass the keys in and the drawing out until the pty closes."""
    watched = [tty] if keys is None else [tty, keys]
    pending = b""
    while True:
        ready = select.select(watched, [], [])[0]
        if keys in ready:
            *lines, pending = (pending + os.read(keys, 4096)).split(b"\n")
            for line in lines:
                os.write(tty, line.decode("unicode_escape").encode("latin-1"))
        if tty in ready:
            # The pty of a tmux that has gone reads as empty, or fails (Linux).
            try:
                drawn = os.read(tty, 65536)
            except OSError:
                return
            if not drawn:
                return
            if screen is not None:
                os.write(screen, drawn)


def main() -> None:
    """Attach as the arguments say and relay."""
    parser = argparse.ArgumentParser()
    parser.add_argument("tmux")
    parser.add_argument("socket")
    parser.add_argument("home")
    parser.add_argument("session")
    parser.add_argument("--keys")
    parser.add_argument("--screen")
    args = parser.parse_args()

    tty = attach(args.tmux, args.socket, args.home, args.session)
    # RDWR: no end of file while no writer has the fifo open.
    keys = os.open(args.keys, os.O_RDWR) if args.keys else None
    screen = None
    if args.screen:
        screen = os.open(args.screen, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    relay(tty, keys, screen)


if __name__ == "__main__":
    main()

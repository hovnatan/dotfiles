r"""A terminal for a tmux test: attach to a session in a pty until tmux goes.

usage: pty_client.py <tmux> <socket> <home> <session>
                     [--keys <fifo>] [--screen <file>]
                     [--path <PATH>] [--env <NAME=VALUE>]... [--size <RxC>]

  --keys    each line written to the fifo is sent to tmux as the bytes it
            spells in Python escapes: \x01s is C-a s, \x1b[I a focus-in
  --screen  what tmux sends the terminal to draw, as it comes
  --path    the client's PATH; /usr/bin:/bin without it
  --env     one more variable for the client, beside HOME, PATH and TERM
  --size    the terminal's rows and columns, as 40x120
"""

# ruff: noqa: INP001, CPY001

import argparse
import fcntl
import os
import pty
import select
import struct
import termios


def attach(command: list[str], env: dict[str, str], size: str | None) -> int:
    """Run the command in a new pty of that size; return the pty."""
    pid, tty = pty.fork()
    if pid == 0:
        if size:
            rows, columns = map(int, size.split("x"))
            window = struct.pack("HHHH", rows, columns, 0, 0)
            fcntl.ioctl(0, termios.TIOCSWINSZ, window)
        os.execve(command[0], command, env)  # noqa: S606
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
    parser.add_argument("--path", default="/usr/bin:/bin")
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument("--size")
    args = parser.parse_args()

    env = {"HOME": args.home, "PATH": args.path, "TERM": "xterm-256color"}
    env.update(pair.split("=", 1) for pair in args.env)
    command = [args.tmux, "-S", args.socket, "attach", "-t", "=" + args.session]
    tty = attach(command, env, args.size)
    # RDWR: no end of file while no writer has the fifo open.
    keys = os.open(args.keys, os.O_RDWR) if args.keys else None
    screen = None
    if args.screen:
        screen = os.open(args.screen, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    relay(tty, keys, screen)


if __name__ == "__main__":
    main()

"""The interactive-login part of an ssh command line.

A second shell on the machine a tab is ssh'd into, and nothing else the
first command did: for Cmd-T in an ssh tab (iterm2_api.py) and for the saved
ssh arrangements (scripts/lib/iterm2_ssh_arrangement.py). No iterm2 import,
so scripts/tests/ssh_command_test.py runs it in CI.

    iTerm2 commandLine -> words -> options / destination / remote command
                                     |          |            |
                                     |          kept         dropped
                                     kept, minus DROP

E.g.
    ssh vm                          -> ssh vm
    ssh -p 2222 user@vm ./deploy.sh -> ssh -p 2222 user@vm   (not run twice)
    ssh -N -L 8080:localhost:80 vm  -> ssh vm                (no second tunnel)
    ssh -t vm tmux attach           -> ssh -t vm             (a plain shell)
    ssh -o SendEnv=LC_TMUX_ATTACH vm
                                    -> ssh vm                (the same: no attach)
    ssh vm "tmux new -s main"       -> ssh vm                (a quote, but dropped)
    ssh -o "ProxyCommand x" vm      -> NotReplayableError: a kept word is quoted,
                                       not ours to re-parse
"""

# Beside the Hammerspoon config, not in a package: imported by path.
# ruff: noqa: INP001, CPY001

import re

# OpenSSH's options that take an argument (ssh(1), getopt string in ssh.c).
TAKES_ARG = set("BbcDEeFIiJLlmOoPpQRSWw")

# Options of the first command that the new tab must not repeat: forwards
# (L R D W: a second bind fails with "Address already in use"), and those
# that make it no interactive shell (N no command, f background, T no tty,
# n no stdin, s subsystem, G/V/Q print and exit, O control-master command).
DROP = set("LRDWNfTnsGVQO")

# A word that fish reads back as exactly itself: no quotes, spaces, `$`,
# `;`, globs, `~`, `%`. iTerm2 joins argv with spaces and double-quotes an
# argument with a space, so a kept word outside this set is one whose real
# boundaries or meaning the joined string has lost. Words of the remote
# command are dropped unread, so they may hold anything.
PLAIN = re.compile(r"[A-Za-z0-9@.,_:/=+-]+")

# The -o that sends the login fish its tmux attach request (the saved
# arrangements' attach line, tmux_attach_requested.fish): a remote command
# in all but form, dropped like one. ssh reads option names in any case,
# variable names as written.
ATTACH = re.compile(r"(?i:sendenv)=LC_TMUX_ATTACH")


class NotReplayableError(ValueError):
    """The command line cannot be replayed safely; the message says why."""


def plain(word: str) -> bool:
    """Tell whether fish reads `word` back as exactly itself."""
    return PLAIN.fullmatch(word) is not None


def option(words: list[str], i: int, out: list[str]) -> int:
    """Append the kept flags of option word `words[i]` to `out`.

    Returns the index of the last word it used. One word may bundle flags
    and end in an option with its argument (getopt): -vp2222, -vp 2222.
    Each is re-emitted on its own: -vp2222 -> -v -p 2222.
    """
    word = words[i]
    for j, flag in enumerate(word[1:], 1):
        if flag not in TAKES_ARG:
            if flag not in DROP:
                out.append(f"-{flag}")
            continue

        # The rest of the word is the argument, or else the next word is.
        arg = word[j + 1 :]
        if not arg:
            i += 1
            if i >= len(words):
                msg = f"-{flag} has no argument"
                raise NotReplayableError(msg)
            arg = words[i]
            if not plain(arg):
                msg = f"-{flag} argument {arg!r} is not plain"
                raise NotReplayableError(msg)
        if flag not in DROP and not (flag == "o" and ATTACH.fullmatch(arg)):
            out += [f"-{flag}", arg]
        break
    return i


def interactive(command_line: str) -> str:
    """Return the replay of `command_line`, or raise NotReplayableError."""
    words = command_line.split()
    if not words or not plain(words[0]):
        msg = f"program {words[0] if words else None!r} is not plain"
        raise NotReplayableError(msg)

    # Options up to the first word that is none: the destination ("--"
    # ends them early).
    out = [words[0]]
    i = 1
    while i < len(words):
        word = words[i]
        if word == "--":
            i += 1
            break
        if not word.startswith("-") or word == "-":
            break
        if not plain(word):
            msg = f"option {word!r} is not plain"
            raise NotReplayableError(msg)
        i = option(words, i, out) + 1

    if i >= len(words):
        msg = "no destination"
        raise NotReplayableError(msg)
    destination = words[i]
    if not plain(destination):
        msg = f"destination {destination!r} is not plain"
        raise NotReplayableError(msg)
    out.append(destination)
    return " ".join(out)

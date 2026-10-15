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
    ssh "user@vm"                   -> ssh user@vm           (iTerm2's quotes off)
    ssh -p 2222 "user@vm" ./deploy.sh
                                    -> ssh -p 2222 user@vm   (not run twice)
    ssh -N -L 8080:localhost:80 vm  -> ssh vm                (no second tunnel)
    ssh -t vm tmux attach           -> ssh -t vm             (a plain shell)
    ssh -o "SendEnv=LC_TMUX_ATTACH" vm
                                    -> ssh vm                (the same: no attach)
    ssh -o SendEnv=LC_LOGIN_DIR vm  -> ssh vm                (nor the saved cd)
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
# `;`, globs, `~`, `%`. A kept word outside this set is one whose real
# boundaries or meaning the joined string has lost. Words of the remote
# command are dropped unread, so they may hold anything.
PLAIN = re.compile(r"[A-Za-z0-9@.,_:/=+-]+")

# iTerm2 (3.7.4, probed through its API with an argument per printable
# ASCII character) joins argv with spaces, quoting an argument unless it is
# all [A-Za-z0-9%,./:_-], with no escapes inside the quotes:
#   holds one of !"$()\` -> '...'   a!b -> 'a!b'
#   else                  -> "..."   user@vm -> "user@vm", a b -> "a b"
# So a word "X" with no space or quote in X is the argument X itself, and is
# read back as X. Any other quoted word (a piece of an argument with a space,
# or a '...' one) is left as it is, for plain() to refuse.
#   "user@vm" -> user@vm
#   "a b"     -> the words `"a` and `b"`, left as they are: refused
ITERM2_QUOTED = re.compile(r'"([^"\s]+)"')

# The -o that sends the login fish its tmux attach request or its directory
# (the saved arrangements' lines, tmux_attach_requested.fish and
# login_dir_requested.fish): a remote command in all but form, dropped like
# one; the arrangement adds its own again when it saves the tab. ssh reads
# option names in any case, variable names as written.
SENT = re.compile(r"(?i:sendenv)=(?:LC_TMUX_ATTACH|LC_LOGIN_DIR)")


class NotReplayableError(ValueError):
    """The command line cannot be replayed safely; the message says why."""


def unquote(word: str) -> str:
    """Return `word` without iTerm2's quotes, where they are unambiguous."""
    m = ITERM2_QUOTED.fullmatch(word)
    return m.group(1) if m else word


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
        if flag not in DROP and not (flag == "o" and SENT.fullmatch(arg)):
            out += [f"-{flag}", arg]
        break
    return i


def interactive(command_line: str) -> str:
    """Return the replay of `command_line`, or raise NotReplayableError."""
    words = [unquote(word) for word in command_line.split()]
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

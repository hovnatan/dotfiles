"""ssh_command.interactive: an iTerm2 commandLine in, the replay out.

The replay is what Cmd-T types into the new tab and what an ssh arrangement
saves; NotReplayableError where it must not guess.

    python3 ssh_command_test.py <repo> <event log>
"""

# A test script, not a package.
# ruff: noqa: INP001, CPY001

import importlib.util
import sys
from datetime import UTC, datetime
from pathlib import Path

REPO, LOG = Path(sys.argv[1]), Path(sys.argv[2])
log_file = LOG.open("a", buffering=1)


def log(msg: str) -> None:
    """Log a UTC-stamped line to the event log and stdout."""
    line = f"{datetime.now(UTC):%Y-%m-%dT%H:%M:%SZ} {msg}"
    log_file.write(line + "\n")
    print(line, flush=True)  # noqa: T201


spec = importlib.util.spec_from_file_location(
    "ssh_command",
    REPO / "home/.hammerspoon/ssh_command.py",
)
assert spec  # noqa: S101
assert spec.loader  # noqa: S101
ssh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ssh)

# commandLine -> expected replay; None where the replay must be refused.
CASES: list[tuple[str, str | None]] = [
    # A plain login and its options stay as they are.
    ("ssh vm", "ssh vm"),
    ("ssh -p 2222 user@vm", "ssh -p 2222 user@vm"),
    ("/usr/bin/ssh -A -J jump vm", "/usr/bin/ssh -A -J jump vm"),
    ("ssh ssh://user@vm:2222", "ssh ssh://user@vm:2222"),
    # A remote command is not run a second time.
    ("ssh -p 2222 user@vm ./deploy.sh", "ssh -p 2222 user@vm"),
    ("ssh vm sudo reboot", "ssh vm"),
    ("ssh -t vm tmux attach", "ssh -t vm"),
    # So is the arrangement's attach, which is one in all but form.
    ("ssh -o SendEnv=LC_TMUX_ATTACH -p 2222 vm", "ssh -p 2222 vm"),
    ("ssh -osendenv=LC_TMUX_ATTACH vm", "ssh vm"),
    # Option names are read in any case, variable names are not.
    ("ssh -o SendEnv=lc_tmux_attach vm", "ssh -o SendEnv=lc_tmux_attach vm"),
    ("ssh -o SendEnv=LC_OTHER vm", "ssh -o SendEnv=LC_OTHER vm"),
    # rsync's and git's transport ssh: a shell, never their server command.
    ("ssh vm rsync --server -vlogDtpre.iLsfxCIvu . /data", "ssh vm"),
    # Forwards and no-shell options are dropped.
    ("ssh -N -L 8080:localhost:80 vm", "ssh vm"),
    ("ssh -fNT -R 9000:localhost:9000 vm", "ssh vm"),
    ("ssh -s vm sftp", "ssh vm"),
    # getopt bundling and an attached argument.
    ("ssh -vp2222 vm", "ssh -v -p 2222 vm"),
    ("ssh -vp 2222 vm", "ssh -v -p 2222 vm"),
    ("ssh -o ServerAliveInterval=30 vm uptime", "ssh -o ServerAliveInterval=30 vm"),
    ("ssh -- vm", "ssh vm"),
    # A remote command is dropped unread, quotes and all.
    ('ssh vm "echo $HOME"', "ssh vm"),
    ("ssh vm 'ls'", "ssh vm"),
    ('ssh -t vm "tmux new -A -s main"', "ssh -t vm"),
    # A kept word the joined string cannot carry back safely: refused.
    ('ssh -o "ProxyCommand ssh -W %h:%p jump" vm', None),
    ("ssh -p$((1)) vm", None),
    ("ssh vm;rm", None),
    ('"/opt/my ssh/ssh" vm', None),
    ("ssh -i ~/.ssh/key vm", None),
    ("ssh -o ControlPath=/tmp/ssh-%C vm", None),
    ("ssh", None),
    ("ssh -p", None),
    ("", None),
]

passed = failed = 0
for command_line, want in CASES:
    try:
        got, why = ssh.interactive(command_line), ""
    except ssh.NotReplayableError as e:
        got, why = None, str(e)
    if got == want and (got is not None or why):
        passed += 1
        log(f"PASS {command_line:<50} -> {got or 'refused: ' + why}")
    else:
        failed += 1
        log(f"FAIL {command_line:<50} -> {got or why} (want {want or 'refused'})")

log(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

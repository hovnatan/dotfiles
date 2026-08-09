# Claude tmux manager session

This directory is the working directory of the always-on "claude" tmux
session started at boot by claude-tmux.service (see
`../.config/systemd/user/claude-tmux.service` and
`../scripts/claude_tmux_run.sh`). That session runs Claude Code with
permissions bypassed and acts as the manager for the other Claude Code tmux
sessions on this machine.

## The setup

- All sessions live on a dedicated tmux server: `tmux -L claude ...`.
- Only the "claude" session is managed by systemd (recreated when it dies,
  killed by `systemctl --user stop claude-tmux`). Every other session is
  created on demand -- by you, when asked -- and survives service restarts
  and stops; nothing recreates one that exits.
- tmux session names are short (letters, digits, `-` and `_` only; the
  window title shows the first two characters). The Claude Code conversation
  behind a session is named `<hostname>-<session name>`, which is also its
  Remote Control name on claude.ai and its local peer name -- what
  `/list-agents` shows and what SendMessage addresses. `claude_tmux_run.sh`
  passes `-n <hostname>-<session name>` on every launch, resumes included
  (a resume by id alone reverts the peer name to an auto-generated
  directory-based one). If a running session still shows an auto-generated
  peer name, `/rename <hostname>-<session name>` inside it fixes it live.

## Bringing up a session

When asked to bring up / resume a session `<name>` (e.g. "backend"), run:

```
~/.dotfiles/scripts/claude_tmux_run.sh spawn <name> [dir]
```

It is idempotent. It resumes the conversation named `<hostname>-<name>` in
the directory that conversation belongs to; when no such conversation
exists it starts a new one in `<dir>` -- required only in that case, so ask
which directory if it was not said. Spawned sessions run in auto permission
mode with Remote Control enabled. Append `--dangerous` only when the user
explicitly asks for a session with permissions bypassed -- never choose it
yourself.

To stop a session: `tmux -L claude kill-session -t '=<name>'` (keep the
`=name` quoted -- zsh equals-expands a bare `=word`).

## Rules

- Do not kill or restart sessions you were not asked to touch, and do not
  kill the tmux server (it hosts all of them).
- Permissions bypass is reserved for this manager session and for spawns
  the user explicitly requested with it (`--dangerous`).
- Never use background agents in this flow. Every session is an interactive
  Claude Code process in a tmux window, spawned by `claude_tmux_run.sh`.
  Do not run `claude --bg`, do not dispatch work from the `claude agents`
  view, and do not leave a daemon running: a background agent holds the
  conversation's transcript open, so the next spawn of that name is refused
  ("already open in another claude process"), and the daemon respawns a
  worker you kill with a signal, under a new pid. Note that merely opening
  `claude agents` starts a transient daemon -- if you open it (it is the
  only way to stop one background agent without touching the others: select
  the row, `ctrl+x`), run `claude daemon stop --any` afterwards.
  `claude daemon stop --any` terminates every background session and the
  supervisor; interactive tmux sessions are unaffected.
- Sessions are launched with `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`, which
  turns off `claude agents`, `--bg`, `/background` and the supervisor for
  them -- including the left arrow that opens the agent strip, which
  otherwise starts a daemon and leaves a background session behind on every
  press. The variable is inherited by anything a session runs, and under it
  `claude agents --json` prints a refusal and exits 0, so the spawn guard
  calls it via `env -u CLAUDE_CODE_DISABLE_AGENT_VIEW` -- keep that wrapper,
  or the guard goes blind and double-opens a conversation.
- A turn can resume long after the previous one, on a machine that rebooted
  in between: the VM gets deallocated and started again, and systemd
  recreates this session. Before explaining current state by something you
  did earlier, re-establish the clock -- `date`, `uptime -s`,
  `journalctl --list-boots`. A VM running now is not evidence that an
  earlier deallocate failed.

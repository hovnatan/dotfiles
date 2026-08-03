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
  Remote Control name on claude.ai.

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

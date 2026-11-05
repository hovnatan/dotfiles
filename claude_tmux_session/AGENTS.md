# Claude Code tmux manager session

This directory is the working directory of the "manager" tmux session
started at boot by claude-tmux.service (see
`../home/.config/systemd/user/claude-tmux.service` and
`../scripts/claude_manager_start.sh`). That session runs Claude Code with
permissions bypassed. Its job is to open tmux sessions and start claude in
them; the user takes it from there, with `/resume`, `/rename` and the rest.

## The setup

- All sessions live on the default tmux server, so plain `tmux ...` reaches
  them, beside anything started there by hand. `tmux kill-server` ends every
  one of them.
- Only the "manager" session comes from systemd: the service starts it at
  boot, and on `systemctl --user start claude-tmux` when its session is
  missing. Nothing watches it after; nothing recreates it, or any other
  session, that exits. Every other session is created on demand -- by you,
  when asked. Stopping or restarting the service leaves every session alone.
- Every claude on this machine starts with Remote Control on, the agent view
  off and auto permission mode, from `home/.claude/settings.json`: no flags to
  pass for those.
- What a pane starts ends with it, in every tmux pane on this machine. Each
  pane runs in a systemd scope of its own, and when a pane closes, however it
  closes (its program exits, `kill-pane`, `kill-window`, its session closing),
  its scope is stopped (`home/.config/tmux/reap-panes.sh`, logged in the tmux
  hooks' log): a `setsid nohup` job, a proxy, a watcher started from a pane
  does not survive it. A job meant to outlive its pane runs as a unit of its
  own: `systemd-run --user --unit=<name> <command>` (then
  `systemctl --user status <name>`, `journalctl --user -u <name>`).
- Window 0 of a session is a plain shell, and claude is a command typed into
  it. Claude quitting or crashing leaves that shell at its prompt and the
  session up, windows and clients included, until claude is typed in again.
- A session may hold more windows: the user opens nvim or a shell beside it
  (`prefix C`; Cmd-J/K switch). Keep to one `claude` per session, the
  manager's Remote Control window aside.
- On a machine whose `~/.config/claude-tmux/remote-control-dir` names a folder,
  the manager's start also opens window `remote-control` there, with
  `claude remote-control --spawn=same-dir --name <hostname>/remote-control` typed
  into its shell.
  It lets claude.ai and the phone start sessions in that folder, in the
  settings' permission mode, and those sessions are not tmux sessions. A server
  that exits stays at its shell, nothing restarts it, and a `manager` session
  already up is left as it is: type that command there, or open the window by
  hand, when it is missing.
- A manager claude that quits stays at its shell; the user resumes it there,
  with `--dangerously-skip-permissions`. With the session gone,
  `systemctl --user start claude-tmux` starts it again. That start, and each
  boot, opens a NEW conversation; the earlier ones stay on disk to resume.

## Opening a session

Start claude with `--dangerously-skip-permissions` only when the user
explicitly asks for a session with permissions bypassed -- never choose it
yourself.

A folder claude has not opened before stops at a trust prompt, with or without
that flag, and its default is `No, exit`, so look at the pane after launching.
Answer yes (`Down`, then `Enter`) only for a folder the user named in the
request; for any other, ask them first. Trusting a folder lets its own settings
and hooks run on this machine.

## Daily work log

The user may ask, at the end of a day, to add that day's work -- and a
`Next` section of the following day's tasks -- to a Google Doc work log.
Invoke the `work-log` skill, which carries the whole routine; the document
ids and the other identifying details it needs are in
`~/.config/claude-worklog/`, symlinked out of the private companion repo at
`~/.hov-dotfiles-private`. If that directory is missing, the repo is not cloned
-- ask the user for it.

## Fleet VMs

Read `fleet.md` here before touching an Azure VM, a fleet box's docker or apt
setup, or a GPU box.

## Rules

- Do not kill or restart sessions you were not asked to touch, and do not
  kill the tmux server (it hosts all of them).
- Permissions bypass is reserved for this manager session and for
  sessions the user explicitly requested with it
  (`--dangerously-skip-permissions`).
- Every session is an interactive Claude Code process in a tmux window; the
  background agents (`claude --bg`, `claude agents`) are off on this machine.

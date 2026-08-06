My linux config files


To setup standalone:

```
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/scripts/setup_user_standalone.sh -o ~/setup_user_standalone.sh
bash -x ~/setup_user_standalone.sh
```

For setup symlinks:

```
git clone https://github.com/hovnatan/dotfiles.git ~/.dotfiles
bash -x ~/.dotfiles/scripts/setup_user_symlinks.sh
```

## Claude Code in tmux from boot (VMs)

Runs an always-on manager tmux session `claude` at boot: Claude Code with
permissions bypassed, started in `~/.dotfiles/claude_tmux_session`, restarted
whenever it exits. Ask it (e.g. over Remote Control) to bring up other
sessions: per `claude_tmux_session/CLAUDE.md` it resumes the conversation
named `<hostname>-<name>` -- also its Remote Control name on claude.ai -- in
a tmux session `<name>` running in auto permission mode (permissions
bypassed only on explicit request). Spawned sessions are
unmanaged: they survive service restarts and stops, and nothing recreates one
that exits. Opt-in per machine:

```
bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh
```

On a fresh machine, run `claude` once in `~/.dotfiles` first and accept the
workspace trust dialog; the manager starts inside the repo and would
otherwise sit at that prompt, invisible, in its detached pane.

```
tmux -L claude attach -t claude            # attach (any session name works)
systemctl --user status claude-tmux        # is it up?
journalctl --user -u claude-tmux -f        # logs
systemctl --user stop claude-tmux          # stop until next boot
systemctl --user disable --now claude-tmux # off for good
sudo loginctl disable-linger $USER         # also stop the user manager at boot
```

Quitting claude inside the manager session makes systemd recreate it after
~10s. To leave it running instead, detach (prefix `d`) rather than quitting.
Since the manager runs with permissions bypassed from boot, only enable this
on a machine whose SSH access you trust.

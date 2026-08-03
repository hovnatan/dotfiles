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

Runs Claude Code in tmux sessions started at boot and restarted whenever they
exit. A built-in session `claude` always runs with permissions bypassed; extra
session names (run in auto permission mode) and the directory they start in
come from `~/.config/claude-tmux.conf`. Each session resumes the Claude Code
conversation named `<hostname>-<session>` -- also its Remote Control name on
claude.ai -- creating it on first run. Opt-in per machine:

```
bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh ~/my_workspace
```

The argument seeds the config's `workdir` (default `$HOME`); after that, edit
`~/.config/claude-tmux.conf` to change the workdir or the `sessions` list.

```
tmux -L claude attach -t claude            # attach (any name from the file)
systemctl --user status claude-tmux        # is it up?
journalctl --user -u claude-tmux -f        # logs
systemctl --user stop claude-tmux          # stop until next boot
systemctl --user disable --now claude-tmux # off for good
sudo loginctl disable-linger $USER         # also stop the user manager at boot
```

Quitting claude inside a session makes systemd recreate that session after
~10s (the others are left alone). To leave it running instead, detach (prefix
`d`) rather than quitting. Adding a name to the file is picked up within
seconds; removing one stops managing that session but does not kill it. Since
the `claude` session runs with permissions bypassed from boot, only enable
this on a machine whose SSH access you trust.

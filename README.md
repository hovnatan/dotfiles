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

Runs `claude --dangerously-skip-permissions` in a tmux session named `claude`,
started at boot and restarted whenever it exits. Opt-in per machine:

```
bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh ~/my_workspace
```

The argument is the directory the session starts in (default `$HOME`); change it
later in `~/.config/claude-tmux.env`.

```
tmux attach -t claude                      # attach
systemctl --user status claude-tmux        # is it up?
journalctl --user -u claude-tmux -f        # logs
systemctl --user stop claude-tmux          # stop until next boot
systemctl --user disable --now claude-tmux # off for good
sudo loginctl disable-linger $USER         # also stop the user manager at boot
```

Quitting claude inside the session makes systemd start a fresh one after ~10s.
To leave it running instead, detach (prefix `d`) rather than quitting. Since it
runs with permissions bypassed from boot, only enable this on a machine whose
SSH access you trust.

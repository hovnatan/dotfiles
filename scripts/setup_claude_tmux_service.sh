#!/usr/bin/env bash

# Run the Claude Code manager in a tmux session "claude" from boot,
# restarting it whenever it exits. The session starts in
# ~/.dotfiles/claude_tmux_session, whose CLAUDE.md tells it how to spawn and
# resume the other Claude Code tmux sessions on demand. Opt-in per machine
# -- not part of setup_user_symlinks.sh.
#
#   bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh

set -e

if ! command -v sudo &> /dev/null; then
  SUDO=""
else
  SUDO=sudo
fi

mkdir -p ~/.config/systemd/user
ln -sfn ~/.dotfiles/.config/systemd/user/claude-tmux.service ~/.config/systemd/user/claude-tmux.service
# Config files from earlier versions of this service; everything is
# hardcoded now.
rm -f ~/.config/claude-tmux.env ~/.config/claude-tmux.conf

# Without lingering, the user manager only runs while you are logged in, so the
# service would not start at boot and would die when you disconnect.
$SUDO loginctl enable-linger "$USER"

systemctl --user daemon-reload
systemctl --user enable claude-tmux.service
systemctl --user restart claude-tmux.service

echo
systemctl --user --no-pager status claude-tmux.service | head -4
echo
echo "Attach with: tmux -L claude attach -t claude"

#!/usr/bin/env bash

# Run Claude Code in a tmux session named "claude" from boot, restarting it
# whenever it exits. Opt-in per machine -- not part of setup_user_symlinks.sh.
#
#   bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh [WORKDIR]
#
# WORKDIR is where the session starts, default $HOME.
# Attach with: tmux -L claude attach -t claude

set -e

if ! command -v sudo &> /dev/null; then
  SUDO=""
else
  SUDO=sudo
fi

WORKDIR="${1:-$HOME}"
if [ ! -d "$WORKDIR" ]; then
  echo "No such directory: $WORKDIR" >&2
  exit 1
fi

mkdir -p ~/.config/systemd/user
ln -sfn ~/.dotfiles/.config/systemd/user/claude-tmux.service ~/.config/systemd/user/claude-tmux.service
echo "CLAUDE_TMUX_DIR=$(cd "$WORKDIR" && pwd)" > ~/.config/claude-tmux.env

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

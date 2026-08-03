#!/usr/bin/env bash

# Run Claude Code in tmux sessions from boot, restarting them whenever they
# exit. A built-in session "claude" always runs (permissions bypassed);
# extra sessions (auto permission mode) and the working directory come from
# ~/.config/claude-tmux.conf (seeded below); each session resumes the Claude
# Code conversation with the same name. Opt-in per machine -- not part of
# setup_user_symlinks.sh.
#
#   bash -x ~/.dotfiles/scripts/setup_claude_tmux_service.sh [WORKDIR]
#
# WORKDIR seeds the config's workdir, default $HOME; if the config already
# exists it is left alone -- edit it instead.
# Attach with: tmux -L claude attach -t claude

set -e

if ! command -v sudo &> /dev/null; then
  SUDO=""
else
  SUDO=sudo
fi

mkdir -p ~/.config/systemd/user
ln -sfn ~/.dotfiles/.config/systemd/user/claude-tmux.service ~/.config/systemd/user/claude-tmux.service
if [ ! -e ~/.config/claude-tmux.conf ]; then
  WORKDIR="${1:-$HOME}"
  if [ ! -d "$WORKDIR" ]; then
    echo "No such directory: $WORKDIR" >&2
    exit 1
  fi
  cat > ~/.config/claude-tmux.conf <<EOF
# Config for claude-tmux.service, sourced as shell by claude_tmux_run.sh.

# Directory the sessions start in.
workdir="$(cd "$WORKDIR" && pwd)"

# tmux sessions besides the built-in "claude" one, one name per line
# (letters, digits, - and _ only). Each runs Claude Code in auto permission
# mode and resumes the Claude Code conversation named "<hostname>-<name>",
# creating it on first run.
sessions=(
)
EOF
else
  echo "Keeping existing ~/.config/claude-tmux.conf; edit it to change workdir/sessions."
fi

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
echo "Sessions and workdir come from ~/.config/claude-tmux.conf."

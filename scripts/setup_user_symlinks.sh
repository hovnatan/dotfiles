#!/usr/bin/env bash

# set -e

# rm -rf ~/.tmux.conf ~/.zshrc ~/.bashrc_local ~/.vimrc ~/.bashrc_local ~/.config/htop ~/.ssh/config

if ! command -v sudo &> /dev/null; then
  SUDO=""
else
  SUDO=sudo
fi
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends curl wget sudo htop tmux zsh vim git openssh-client make locales
$SUDO locale-gen --no-purge en_US.UTF-8

cd ~

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/.tmux.conf ~/.tmux.conf
mkdir -p ~/.tmux/logs

[ -L ~/.zshrc ] && rm -f ~/.zshrc
if ! grep -qs '\.zshrc\.shared' ~/.zshrc; then
cat <<EOT >> ~/.zshrc
if [[ -f "\$HOME/.dotfiles/.zshrc.shared" ]]; then
  source "\$HOME/.dotfiles/.zshrc.shared"
fi
EOT
fi

mkdir -p ~/.vimundo/
rm -rf ~/.vimrc
ln -s ~/.dotfiles/.vimrc ~/.vimrc

# # Check if .bashrc_local is already sourced in .bashrc
# if ! grep -q '\.bashrc_local' ~/.bashrc; then
#     cat <<EOT >> ~/.bashrc
# if [[ -f "\$HOME/.bashrc_local" ]]; then
#     source "\$HOME/.bashrc_local"
# fi
# EOT
# fi
# rm -rf ~/.bashrc_local
# ln -s ~/.dotfiles/.bashrc_local ~/.bashrc_local


rm -rf ~/.config/git
ln -s ~/.dotfiles/.config/git ~/.config/git

# Machine-local git config — not tracked in dotfiles. It pulls in the shared,
# tracked config.shared via [include], and also receives `git config --global`
# writes and tool injections (safe.directory, ...), keeping config.shared clean.
if ! grep -qs 'config\.shared' ~/.gitconfig; then
    cat <<EOT >> ~/.gitconfig
[include]
  path = ~/.config/git/config.shared
[user]
  email =
# [core]
#   sshCommand = ssh -i ~/.ssh/hk_dev.pem -F /dev/null
[credential]
  helper = "!f() { echo \"username=x-access-token\"; echo \"password=\$GH_TOKEN\"; }; f"
EOT
fi

mkdir -p ~/.config
rm -rf ~/.config/htop
ln -s ~/.dotfiles/.config/htop ~/.config/

# cd ~
# ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519
# ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
#chmod 644 ~/.ssh/config
# touch ~/.ssh/authorized_keys
# chmod 600 ~/.ssh/authorized_keys
mkdir -p ~/.ssh
ln -s ../.dotfiles/.ssh/config ~/.ssh/config

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_ed25519.pub into the field labeled 'Key'. with xclip -i -selection clipboard ~/.ssh/id_ed25519.pub

# cd ~/.dotfiles
# git remote set-url origin git@github.com:hovnatan/dotfiles.git

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt

# sudo gpasswd -a $USER docker

# mkdir -p ~/.config/Cursor/User
# ln -sf ~/Dropbox/scripts/Cursor/User/keybindings.json ~/.config/Cursor/User/keybindings.json
# ln -sf ~/Dropbox/scripts/Cursor/User/settings.json ~/.config/Cursor/User/settings.json

mkdir -p ~/.codex
ln -sf ~/.dotfiles/.codex/config.toml ~/.codex/config.toml

mkdir -p ~/.claude
ln -sf ~/.dotfiles/.claude/settings.json ~/.claude/settings.json
ln -sf ~/.dotfiles/.claude/CLAUDE.md ~/.claude/CLAUDE.md

# Claude Code personal skills — keep ~/.claude/skills as a real directory so
# skills installed by other means are left alone, and symlink in each skill
# vendored under .dotfiles/.claude/skills/ (pinned per skill via .upstream;
# see scripts/check_skill_updates.sh).
mkdir -p ~/.claude/skills
for skill in ~/.dotfiles/.claude/skills/*/; do
  [ -d "$skill" ] || continue
  ln -sfn "${skill%/}" ~/.claude/skills/"$(basename "$skill")"
done

# Expose the same skills under ~/.agents/skills for tools that look there.
mkdir -p ~/.agents
rm -rf ~/.agents/skills
ln -s ~/.claude/skills ~/.agents/skills

ln -s ~/.dotfiles/.config/ghostty ~/.config/

mkdir -p ~/.local/{bin,local}
ln -sf ~/.dotfiles/.npmrc ~/.npmrc

ln -sf ~/.dotfiles/.config/uv ~/.config/

mkdir -p ~/.colima/default
ln -sf ~/.dotfiles/.colima/default/colima.yaml ~/.colima/default/colima.yaml

echo -e "\033[33mAdd email to ~/.gitconfig\033[0m"
echo "Done"

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

if ! command -v uv &> /dev/null; then
    curl -LsSf 'astral.sh/uv/install.sh' | sh
fi

cd ~

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/.tmux.conf ~/.tmux.conf
mkdir -p ~/.tmux/logs

rm -rf ~/.zshrc
ln -s ~/.dotfiles/.zshrc ~/.zshrc

mkdir -p ~/.vimundo/
rm -rf ~/.vimrc
ln -s ~/.dotfiles/.vimrc ~/.vimrc

# Check if .bashrc_local is already sourced in .bashrc
if ! grep -q '\.bashrc_local' ~/.bashrc; then
    cat <<EOT >> ~/.bashrc
if [[ -f "\$HOME/.bashrc_local" ]]; then
    source "\$HOME/.bashrc_local"
fi
EOT
fi
rm -rf ~/.bashrc_local
ln -s ~/.dotfiles/.bashrc_local ~/.bashrc_local


if ! grep -q '\.gitconfig_common' ~/.gitconfig; then
    cat <<EOT >> ~/.gitconfig
[include]
  path = ~/.dotfiles/.gitconfig_common
[user]
  name = Hovnatan Karapetyan
  email = 
# [core]
#   sshCommand = ssh -i ~/.ssh/hk_dev.pem -F /dev/null
EOT
vim ~/.gitconfig # add email
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
rm -rf ~/.ssh/config
ln -s ~/.dotfiles/.ssh/config ~/.ssh/config

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

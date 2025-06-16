#!/usr/bin/env bash

# curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/scripts/setup_user_standalone.sh -o ~/setup_user_standalone.sh && bash -x ~/setup_user_standalone.sh

set -e

cd ~

curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.zshrc -o ~/.zshrc

curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.tmux.conf -o ~/.tmux.conf
mkdir -p ~/.tmux/logs

curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.vimrc -o ~/.vimrc
mkdir -p ~/.vim/undodir

if ! grep -q '\.gitconfig_common' ~/.gitconfig; then
    cat <<EOT >> ~/.gitconfig
[include]
  path = ~/.gitconfig_common
[user]
  name = Hovnatan Karapetyan
  email = 
EOT
fi
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.gitconfig_common -o ~/.gitconfig_common


if ! grep -q '\.bashrc_local' ~/.bashrc; then
    cat <<EOT >> ~/.bashrc
if [[ -f "$HOME/.bashrc_local" ]]; then
    source "$HOME/.bashrc_local"
fi
EOT
fi
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.bashrc_local -o ~/.bashrc_local

mkdir -p ~/.ssh
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.ssh/config -o ~/.ssh/config

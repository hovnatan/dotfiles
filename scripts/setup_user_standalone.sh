#!/usr/bin/env bash

# curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/scripts/setup_user.sh -o ~/setup_user.sh && bash -x ~/setup_user.sh

set -e

cd ~

mkdir -p ~/.vim/undodir

curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.tmux.conf -o ~/.tmux.conf
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.zshrc -o ~/.zshrc
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.vimrc -o ~/.vimrc
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.gitconfig_common -o ~/.gitconfig_common
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.bashrc_local -o ~/.bashrc_local
cat <<EOT >> ~/.bashrc
if [[ -f "$HOME/.bashrc_local" ]]; then
    source "$HOME/.bashrc_local"
fi
EOT

cat <<EOT >> ~/.gitconfig
[include]
  path = ~/.gitconfig_common
[user]
  name = Hovnatan Karapetyan
  email = 
EOT

mkdir -p ~/.ssh
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.ssh/config -o ~/.ssh/config

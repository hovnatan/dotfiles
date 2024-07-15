#!/usr/bin/env bash

# curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/scripts/setup_user.sh -o ~/setup_user.sh

set -e

cd ~

mkdir -p ~/.vim/undodir

curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.tmux.conf -o ~/.tmux.conf
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.zshrc -o ~/.zshrc
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.vimrc -o ~/.vimrc
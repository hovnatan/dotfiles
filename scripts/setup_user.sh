#!/usr/bin/env bash

set -e

cd ~

mkdir -p ~/.vim/undodir

curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.tmux.conf -o ~/.tmux.conf
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.zshrc -o ~/.zshrc
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.vimrc -o ~/.vimrc
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.profile_local -o ~/.profile_local

cat <<EOT >> ~/.profile
if [[ -f "\$HOME/.profile_local" ]]; then
    source "\$HOME/.profile_local"
fi
EOT
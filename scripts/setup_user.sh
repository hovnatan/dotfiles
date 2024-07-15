#!/usr/bin/env bash

# curl -H 'cache-control: no-cache, no-store' https://raw.githubusercontent.com/hovnatan/dotfiles/main/scripts/setup_user.sh -o ~/setup_user.sh

set -e

cd ~

mkdir -p ~/.vim/undodir

curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.tmux.conf -o ~/.tmux.conf
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.zshrc -o ~/.zshrc
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.vimrc -o ~/.vimrc
curl https://raw.githubusercontent.com/hovnatan/dotfiles/main/.profile_local -o ~/.profile_local

if ! grep -q ".profile_local" "$HOME/.profile"; then
    cat <<EOT >> $HOME/.profile

if [[ -f "\$HOME/.profile_local" ]]; then
    source "\$HOME/.profile_local"
fi
EOT
fi
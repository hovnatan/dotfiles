#!/bin/bash

set -e

cd ~/.dotfiles

git pull

GIT_BRANCH=$(git branch --show-current)

if [[ "$GIT_BRANCH" != master ]]; then
  git rebase origin/master
  git push -f
fi

sudo apt update
sudo apt -y dist-upgrade
sudo apt -y autoremove

fish -c "fisher update"

"$HOME/.tmux/plugins/tpm/bin/update_plugins" all

source ~/miniconda3/etc/profile.d/conda.sh
conda activate
conda update -y --all

nvim -c 'PlugUpgrade | PlugUpdate'

# wget https://raw.githubusercontent.com/cyrus-and/gdb-dashboard/master/.gdbinit -P $HOME

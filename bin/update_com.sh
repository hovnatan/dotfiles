#!/bin/bash

set -e

sudo echo "Starting upgrade"

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
mamba update -y --all

TMPFILE=$(mktemp /tmp/hk-update-script.XXXXXX)
mamba list | grep "pypi" | cut -d " " -f 1 > $TMPFILE
pip install --upgrade --upgrade-strategy only-if-needed -r $TMPFILE | grep -v "Requirement already satisfied: "
rm $TMPFILE

nvim -c 'PlugUpgrade | PlugUpdate'

# wget https://raw.githubusercontent.com/cyrus-and/gdb-dashboard/master/.gdbinit -P $HOME

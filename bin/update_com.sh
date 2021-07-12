#!/bin/bash

sudo echo "Starting upgrade"

cd ~/.dotfiles
git pull
GIT_BRANCH=$(git branch --show-current)
if [[ "$GIT_BRANCH" != master ]]; then
  git merge origin/master
  git push
fi

# sudo port selfupdate
# sudo port upgrade outdated
brew update
brew upgrade

fish -c "fisher update"

"$HOME/.tmux/plugins/tpm/bin/update_plugins" all

source ~/miniconda3/etc/profile.d/conda.sh
conda activate
conda update -y --all

TMPFILE=$(mktemp /tmp/hk-update-script.XXXXXX)
conda list | grep "pypi" | cut -d " " -f 1 > $TMPFILE
pip install --upgrade --upgrade-strategy only-if-needed -r $TMPFILE | grep -v "Requirement already satisfied: "
rm $TMPFILE

nvim -c 'PackerSync'

# wget https://raw.githubusercontent.com/cyrus-and/gdb-dashboard/master/.gdbinit -P $HOME

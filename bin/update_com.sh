#!/bin/bash

echo "Starting upgrade"

#cd ~/.dotfiles
#git pull
#GIT_BRANCH=$(git branch --show-current)
#if [[ "$GIT_BRANCH" != master ]]; then
#  git rebase origin/master
#  git push -f
#fi

brew update
brew upgrade

fish -c "fisher update"

"$HOME/.tmux/plugins/tpm/bin/update_plugins" all

source ~/miniforge3/etc/profile.d/conda.sh
conda activate
conda update -y --all
 
TMPFILE=$(mktemp /tmp/hk-update-script.XXXXXX)
conda list | grep "pypi" | cut -d " " -f 1 > $TMPFILE
pip install --upgrade --upgrade-strategy only-if-needed -r $TMPFILE | grep -v "Requirement already satisfied: "
rm $TMPFILE

nvim -c 'PackerSync'

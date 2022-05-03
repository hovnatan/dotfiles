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
brew upgrade --cask --greedy

fish -c "fisher update"

"$HOME/.tmux/plugins/tpm/bin/update_plugins" all

nvim -c 'PackerSync'

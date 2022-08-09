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

top_level=( $(pipdeptree --warn silence | grep -E '(^\S+)' | awk -F== '{print$1}' ) )
user_level=( $(pip freeze --user | grep -E '(^\S+)' | awk -F== '{print$1}' ) )

intersect=($(comm -12 <(for X in "${top_level[@]}"; do echo "${X}"; done|sort)  <(for X in "${user_level[@]}"; do echo "${X}"; done|sort)))

pip3 install -U ${intersect[*]// /|}

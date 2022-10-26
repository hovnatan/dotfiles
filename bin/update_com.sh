#!/bin/bash

sudo echo "Starting upgrade"

#cd ~/.dotfiles
#git pull
#GIT_BRANCH=$(git branch --show-current)
#if [[ "$GIT_BRANCH" != master ]]; then
#  git rebase origin/master
#  git push -f
#fi

sudo apt update
sudo apt -y dist-upgrade
sudo apt -y autoremove

sudo snap refresh
sudo fwupdmgr update

fish -c "fisher update"

"$HOME/.config/tmux/plugins/tpm/bin/update_plugins" all

pipdeptree -u --warn silence | grep -E '(^\S+)' | awk -F== '{print$1}' | xargs pip3 install --user -U --upgrade-strategy=eager

npm update -g

rustup update
cargo install-update -a

gup update

nvim -c 'PackerSync'

if [ -f /var/run/reboot-required ]; then 
  echo 'System reboot required'
fi

#!/bin/bash

sudo echo "Starting upgrade"

sudo snap refresh
SNAPS_NOT_UPDATED=$(sudo snap refresh --list 2>&1)
if [ "$SNAPS_NOT_UPDATED" != "All snaps up to date." ]; then
  echo "$SNAPS_NOT_UPDATED"
  exit 1;
fi

sudo apt update
sudo apt -y dist-upgrade
sudo apt -y autoremove

sudo fwupdmgr update

fish -c "fisher update"

"$HOME/.config/tmux/plugins/tpm/bin/update_plugins" all

pipdeptree -u --warn silence | grep -E '(^\S+)' | awk -F== '{print$1}' | xargs pip3 install --user -U --upgrade-strategy=eager

npm update -g

rustup update
cargo install-update -a

gup update

nvim -c 'PackerSync'

RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -f /var/run/reboot-required ]; then 
  echo -e "$RED"
  echo 'System reboot required'
  echo -e "$NC"
fi

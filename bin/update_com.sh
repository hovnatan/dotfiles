#!/usr/bin/env bash

set -e

sudo echo "Starting upgrade"

if type snap > /dev/null; then
  sudo snap refresh
  SNAPS_NOT_UPDATED=$(sudo snap refresh --list 2>&1)
  if [ "$SNAPS_NOT_UPDATED" != "All snaps up to date." ]; then
    echo "$SNAPS_NOT_UPDATED"
    exit 1;
  fi
fi

sudo apt update
sudo NEEDRESTART_MODE=a apt -y dist-upgrade
sudo apt -y autoremove

if type fwupdmgr > /dev/null; then
  sudo fwupdmgr update
fi

if [[ -v HK_DEV_ENV ]]; then
  fish -c "fisher update"

  "$HOME/.config/tmux/plugins/tpm/bin/update_plugins" all

  pipdeptree -u --warn silence | grep -E '(^[a-zA-Z]+)' | awk -F== '{print$1}' | xargs pip3 install --user -U # --upgrade-strategy=eager

  npm install -g yarn@latest
  # rm ~/.config/yarn/global/yarn.lock
  # yarn global add
  yarn global upgrade --latest

  rustup update
  cargo install-update -a

  gup update

  nvim -c "MasonUpdate" -c "lua require('lazy').sync()"
fi

RED='\033[0;31m'
NC='\033[0m' # No Color

if [ -f /var/run/reboot-required ]; then 
  echo -e "$RED"
  echo 'System reboot required'
  echo -e "$NC"
fi

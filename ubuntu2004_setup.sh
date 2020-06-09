#!/bin/bash

set -e

sudo apt-get update

sudo apt-get install -y software-properties-common jq feh w3m-img tmux fzf fd-finder ripgrep fish ranger zathura clang clangd bear ppa-purge


sudo apt-get install gawk


curl -sL https://deb.nodesource.com/setup_13.x | sudo -E bash -
sudo apt-get install -y nodejs

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install -y yarn

sudo apt-get install python3-pip
pip3 install --user pylint yapf jedi neovim

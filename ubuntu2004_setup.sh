#!/bin/bash

set -e

sudo apt-get update

sudo apt-get install -y software-properties-common jq feh w3m-img tmux fzf fd-find ripgrep fish ranger clang clangd bear ppa-purge valgrind curl neovim

# sudo apt-get install -y texlive-latex-extra latexmk chrome-gnome-shell zathura xrdp fonts-croscore kitty
# sudo apt-get install -y i3 i3blocks
# sudo apt-get install -y mesa-utils freeglut3-dev



sudo apt-get install gawk


curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get install -y nodejs

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install -y yarn

sudo apt-get install python3-pip
pip3 install --user pylint yapf jedi neovim

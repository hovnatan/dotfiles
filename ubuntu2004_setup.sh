#!/bin/bash

set -e

sudo apt-get install -y software-properties-common

sudo add-apt-repository multiverse
sudo add-apt-repository universe
sudo add-apt-repository restricted

sudo apt-get update
sudo apt-get -y dist-upgrade

sudo apt-get install -y software-properties-common jq feh w3m-img tmux fzf fd-find ripgrep fish ranger clang clangd clang-format clang-tidy bear ppa-purge valgrind curl neovim htop octave libfreetype6-dev libfontconfig1-dev libxext-dev libxcb-render-util0-dev libxcb-shape0-dev libxcb-xfixes0-dev build-essential libxft-dev net-tools sshfs cmake rustc cargo aria2 mediainfo xdg-utils wmctrl awscli docker.io default-jre universal-ctags

sudo apt-get install -y meld xrdp remmina zathura qtcreator

# sudo apt-get install -y texlive-latex-extra latexmk chrome-gnome-shell zathura xrdp fonts-croscore kitty
# sudo apt-get install -y i3 i3blocks
# sudo apt-get install -y mesa-utils freeglut3-dev

sudo apt-get install -y gawk

curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get install -y nodejs

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install -y yarn

sudo apt-get install -y python2 python3-pip
pip3 install --user pylint yapf jedi neovim ueberzug

sudo update-alternatives --install /usr/bin/python python /usr/bin/python2 1
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 2

sudo rm -f /usr/share/fish/completions/zathura.fish

mkdir -p ~/Downloads
cd ~/Downloads
git clone https://git.suckless.org/tabbed
cd tabbed
ln -s ~/.dotfiles/tabbed/config.h .
make
ln -s "$PWD"/tabbed ~/.dotfiles/bin/tabbed

sudo nvim /etc/sysctl.d/10-ptrace.conf

# sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/7fa2af80.pub
# sudo sh -c 'echo "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64 /" > /etc/apt/sources.list.d/cuda.list'
# sudo apt-get update
# sudo apt-get install -y cuda-toolkit-11-0


# cargo install --git https://github.com/nbdd0121/x11-over-vsock

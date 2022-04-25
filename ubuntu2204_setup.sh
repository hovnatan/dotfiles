#!/bin/bash

set -e

sudo apt-add-repository ppa:fish-shell/release-3

sudo apt-get install -y software-properties-common

sudo add-apt-repository multiverse
sudo add-apt-repository universe
sudo add-apt-repository restricted

sudo apt-get update
sudo apt-get -y dist-upgrade

sudo apt-get install -y software-properties-common jq feh w3m-img tmux fzf fd-find ripgrep fish ranger clang clangd clang-format clang-tidy bear ppa-purge valgrind curl neovim htop octave libfreetype6-dev libfontconfig1-dev libxext-dev libxcb-render-util0-dev libxcb-shape0-dev libxcb-xfixes0-dev build-essential libxft-dev net-tools sshfs cmake rustc cargo aria2 mediainfo xdg-utils wmctrl awscli docker.io default-jre universal-ctags gcc-10 g++-10 aptitude pandoc poppler-utils ffmpeg git-lfs ripgrep libfuse2

sudo apt-get install -y xrdp remmina 
cargo install exa

# sudo apt-get install -y texlive-latex-recommended texlive-pictures texlive-latex-extra latexmk
# sudo apt-get install chrome-gnome-shell zathura xrdp fonts-croscore kitty
# sudo apt-get install -y i3 i3blocks
# sudo apt-get install -y mesa-utils freeglut3-dev

sudo apt-get install -y gawk

sudo apt-get install -y python2 python3-pip
pip3 install --user pylint yapf jedi neovim ueberzug

sudo update-alternatives --install /usr/bin/python python /usr/bin/python2 1
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 2

sudo rm -f /usr/share/fish/completions/zathura.fish

sudo nvim /etc/sysctl.d/10-ptrace.conf

# ubuntu-drivers devices
# sudo ubuntu-drivers autoinstall
wget https://github.com/neovim/neovim/releases/download/v0.7.0/nvim.appimage -O ~/.dotfiles/bin/nvim
chmod +x ~/.dotfiles/bin/nvim

sudo npm i -g pyright

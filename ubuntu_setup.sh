#!/bin/bash

wget https://github.com/neovim/neovim/releases/download/v0.4.3/nvim.appimage
mv nvim.appimage ~/.dotfiles/bin/nvim
chmod +x ~/.dotfiles/bin/nvim

wget https://github.com/sharkdp/fd/releases/download/v7.4.0/fd-musl_7.4.0_amd64.deb
sudo dpkg -i fd-musl_7.4.0_amd64.deb

sudo apt install gawk

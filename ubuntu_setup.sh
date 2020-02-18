#!/bin/bash

wget https://github.com/neovim/neovim/releases/download/v0.4.3/nvim.appimage
mv nvim.appimage ~/.dotfiles/bin/nvim
chmod +x ~/.dotfiles/bin/nvim

wget https://github.com/sharkdp/fd/releases/download/v7.4.0/fd-musl_7.4.0_amd64.deb
sudo dpkg -i fd-musl_7.4.0_amd64.deb

sudo apt install gawk

sudo apt-add-repository ppa:fish-shell/release-3
sudo apt-get update
sudo apt-get install fish

wget https://github.com/junegunn/fzf-bin/releases/download/0.20.0/fzf-0.20.0-linux_amd64.tgz
tar xf fzf-0.20.0-linux_amd64.tgz
mv fzf ~/.dotfiles/bin

REPO="https://github.com/BurntSushi/ripgrep/releases/download/"
RG_LATEST=$(curl -sSL "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" | jq --raw-output .tag_name)
RELEASE="${RG_LATEST}/ripgrep-${RG_LATEST}-x86_64-unknown-linux-musl.tar.gz"

TMPDIR=$(mktemp -d)
cd $TMPDIR
wget -O - ${REPO}${RELEASE} | tar zxf - --strip-component=1
mv rg ~/.dotfiles/bin

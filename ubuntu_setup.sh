#!/bin/bash

set -e

sudo apt-get update

sudo apt-get install -y software-properties-common jq feh w3m-img

wget https://github.com/neovim/neovim/releases/download/v0.4.3/nvim.appimage
mv nvim.appimage ~/.dotfiles/bin/nvim
chmod +x ~/.dotfiles/bin/nvim

wget https://github.com/tmux/tmux/releases/download/3.0a/tmux-3.0a-x86_64.AppImage
mv tmux-3.0a-x86_64.AppImage ~/.dotfiles/bin/tmux
chmod +x ~/.dotfiles/bin/tmux

wget https://github.com/sharkdp/fd/releases/download/v7.4.0/fd-musl_7.4.0_amd64.deb
sudo dpkg -i fd-musl_7.4.0_amd64.deb

sudo apt-get install gawk

sudo apt-add-repository ppa:fish-shell/release-3
sudo apt-get update
sudo apt-get install -y fish

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

tic -x -o $HOME/.terminfo ~/.dotfiles/.terminfo/termite.terminfo
mkdir -p ~/.terminfo/t
cp ~/.dotfiles/.terminfo/tmux-256color ~/.terminfo/t/

curl -sL https://deb.nodesource.com/setup_13.x | sudo -E bash -
sudo apt-get install -y nodejs

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install -y yarn

sudo apt-get install python3-pip
pip3 install --user pylint yapf jedi neovim

git clone git://github.com/wting/autojump.git
cd autojump
./install.py

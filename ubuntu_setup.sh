#!/bin/bash

sudo apt-get update

sudo apt install -y jq tmux python3-neovim

# wget https://github.com/neovim/neovim/releases/download/v0.4.3/nvim.appimage
# mv nvim.appimage ~/.dotfiles/bin/nvim
# chmod +x ~/.dotfiles/bin/nvim

sudo add-apt-repository ppa:neovim-ppa/unstable
sudo apt-get update
sudo apt install -y neovim

wget https://github.com/sharkdp/fd/releases/download/v7.4.0/fd-musl_7.4.0_amd64.deb
sudo dpkg -i fd-musl_7.4.0_amd64.deb

sudo apt install gawk

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

tic -x -o $HOME/.terminfo ~/.dotfiles/.terminfo/tmux.terminfo
tic -x -o $HOME/.terminfo ~/.dotfiles/.terminfo/termite.terminfo

curl -sL https://deb.nodesource.com/setup_13.x | sudo -E bash -
sudo apt-get install -y nodejs

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update
sudo apt install -y yarn

sudo apt install python3-pip
pip install pylint yapf jedi

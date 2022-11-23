#!/bin/bash

set -e

sudo apt-add-repository ppa:fish-shell/release-3
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -

sudo apt-get install -y software-properties-common

sudo add-apt-repository multiverse
sudo add-apt-repository universe
sudo add-apt-repository restricted

sudo apt-get update
sudo apt-get -y dist-upgrade

sudo apt-get install -y jq feh tmux fzf fd-find ripgrep fish ranger clang clangd clang-format clang-tidy bear ppa-purge valgrind curl htop octave net-tools sshfs cmake aria2 mediainfo xdg-utils wmctrl awscli docker.io default-jre universal-ctags aptitude pandoc poppler-utils ffmpeg git-lfs ripgrep libfuse2 bat ubuntu-drivers-common nodejs unzip golang-go sqlite3 libsqlite3-dev shellcheck gawk libssl-dev python3-venv
if [[ "$WSL_DISTRO_NAME" ]]; then
   sudo apt-get install wslu
fi

# sudo apt-get install -y xrdp remmina
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
. "$HOME/.cargo/env"
cargo install exa stylua cargo-update

# sudo apt-get install -y texlive-latex-recommended texlive-pictures texlive-latex-extra latexmk
# sudo apt-get install chrome-gnome-shell zathura xrdp fonts-croscore kitty
# sudo apt-get install -y i3 i3blocks
# sudo apt-get install -y mesa-utils freeglut3-dev

sudo apt-get install -y python2 python3-pip
pip3 install --user pylint pynvim black pipdeptree pyls-isort python-lsp-server python-lsp-black

sudo update-alternatives --install /usr/bin/python python /usr/bin/python2 1
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 2

sudo vim /etc/sysctl.d/10-ptrace.conf

# ubuntu-drivers devices
# sudo ubuntu-drivers autoinstall
wget https://github.com/neovim/neovim/releases/download/v0.8.0/nvim.appimage -O ~/.dotfiles/bin/nvim
chmod +x ~/.dotfiles/bin/nvim

go install github.com/mattn/efm-langserver@latest
go install github.com/nao1215/gup@latest

cp ~/.dotfiles/.npmrc ~/.npmrc

npm i --location=global yarn
yarn global add bash-language-server prettier pyright vscode-langservers-extracted typescript typescript-language-server

wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/Hack.zip -O ~/Downloads/Hack.zip
mkdir -p ~/.local/share/fonts
unzip ~/Downloads/Hack.zip -d ~/.local/share/fonts
fc-cache -fv

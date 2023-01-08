#!/usr/bin/env bash

set -e

apt-config dump | grep -we Recommends -e Suggests | sed s/1/0/ | sudo tee /etc/apt/apt.conf.d/99norecommend
sudo apt-get update
sudo apt-get -y dist-upgrade
sudo apt-get install -y software-properties-common curl gnupg wget locales

sudo locale-gen --no-purge en_US.UTF-8

sudo apt-add-repository ppa:fish-shell/release-3
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -

sudo add-apt-repository multiverse
sudo add-apt-repository universe
sudo add-apt-repository restricted


sudo apt-get install -y jq feh fzf fd-find ripgrep fish ranger clang clangd clang-format clang-tidy bear valgrind curl htop cmake aria2 mediainfo pandoc git-lfs bat nodejs unzip golang-go sqlite3 libsqlite3-dev shellcheck gawk python3-venv yacc tmux pkg-config libssl-dev build-essential openssh-client libtool-bin gettext automake libevent-dev libncurses-dev tzdata

# sudo apt-get install -y wmctrl awscli docker.io default-jre xdg-utils universal-ctags poppler-utils ffmpeg libfuse2 ubuntu-drivers-common octave ppa-purge net-tools sshfs 
# if [[ "$WSL_DISTRO_NAME" ]]; then
#    sudo apt-get install wslu
# fi

wget https://github.com/dandavison/delta/releases/download/0.14.0/git-delta_0.14.0_amd64.deb -P ~/Downloads/
sudo dpkg -i ~/Downloads/git-delta_0.14.0_amd64.deb

# sudo apt-get install -y xrdp remmina
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
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

# sudo vim /etc/sysctl.d/10-ptrace.conf

# ubuntu-drivers devices
# sudo ubuntu-drivers autoinstall

go install github.com/mattn/efm-langserver@latest
go install github.com/nao1215/gup@latest

npm i --prefix=~/.local --location=global yarn
~/.local/bin/yarn global add bash-language-server prettier pyright vscode-langservers-extracted typescript typescript-language-server

# wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/Hack.zip -O ~/Downloads/Hack.zip
# mkdir -p ~/.local/share/fonts
# unzip ~/Downloads/Hack.zip -d ~/.local/share/fonts
# fc-cache -fv

# type -p curl >/dev/null || sudo apt install curl -y
# curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
#   && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
#   && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
#   && sudo apt update \
#   && sudo apt install gh -y

export MAKEFLAGS="-j11"
export CFLAGS="-march=native -O3"
export CXXFLAGS="-march=native -O3"

cd ~/Downloads
git clone https://github.com/neovim/neovim.git
cd neovim
git checkout stable
make CMAKE_BUILD_TYPE=Release
sudo make install
cd ..

git clone https://github.com/tmux/tmux.git
cd tmux
git checkout 3.3a
sh autogen.sh
./configure && make
sudo make install
cd ..

git clone https://github.com/fish-shell/fish-shell.git
cd fish-shell
git checkout 3.6.0
mkdir build
cd build
cmake ..
make
sudo make install
cd ../..

git clone https://github.com/alacritty/alacritty.git
cd alacritty
sudo tic -xe alacritty,alacritty-direct extra/alacritty.info
cd ..
rm -rf alacritty

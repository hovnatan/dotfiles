#!/usr/bin/env bash

set -e

git clone -b delll https://github.com/hovnatan/dotfiles.git
mv dotfiles .dotfiles
cd .dotfiles
cp .npmrc ..

pip3 install --user pylint pynvim black pipdeptree pyls-isort python-lsp-server python-lsp-black

go install github.com/mattn/efm-langserver@latest
go install github.com/nao1215/gup@latest

npm i --prefix=~/.local --location=global yarn
~/.local/bin/yarn global add bash-language-server prettier pyright vscode-langservers-extracted typescript typescript-language-server

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
. "$HOME/.cargo/env"
cargo install exa stylua cargo-update
cargo install zoxide --locked

# wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/Hack.zip -O ~/Downloads/Hack.zip
# mkdir -p ~/.local/share/fonts
# unzip ~/Downloads/Hack.zip -d ~/.local/share/fonts
# fc-cache -fv

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

export MAKEFLAGS="-j11"
export CFLAGS="-march=native -O3"
export CXXFLAGS="-march=native -O3"

mkdir ~/Downloads
cd ~/Downloads
git clone --depth 1 --branch stable https://github.com/neovim/neovim.git 
cd neovim
make CMAKE_BUILD_TYPE=Release
sudo make install
cd ..

git clone --depth 1 --branch 3.3a https://github.com/tmux/tmux.git
cd tmux
sh autogen.sh
./configure && make
sudo make install
cd ..

git clone --depth 1 --branch 3.6.0 https://github.com/fish-shell/fish-shell.git
cd fish-shell
mkdir build
cd build
cmake ..
make
sudo make install
cd ../..

git clone --depth 1 https://github.com/alacritty/alacritty.git
cd alacritty
sudo tic -xe alacritty,alacritty-direct extra/alacritty.info
cd ..
rm -rf alacritty
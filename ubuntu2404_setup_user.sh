#!/usr/bin/env bash

set -e

cd ~

cp /etc/skel/.* ./ || true
cp /etc/skel/* ./ || true

# git clone -b delll https://github.com/hovnatan/dotfiles.git
# mv dotfiles .dotfiles
# cd .dotfiles
cp .npmrc ..

sudo apt install -y python3-pynvim

go install github.com/nao1215/gup@latest
go install github.com/mattn/efm-langserver@latest

# npm i --prefix=~/.local --location=global yarn

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
. "$HOME/.cargo/env"
cargo install cargo-update
# cargo install atuin

# wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/Hack.zip -O ~/Downloads/Hack.zip
# mkdir -p ~/.local/share/fonts
# unzip ~/Downloads/Hack.zip -d ~/.local/share/fonts
# fc-cache -fv

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --bin

export MAKEFLAGS="-j11"
export CFLAGS="-march=native -O3"
export CXXFLAGS="-march=native -O3"

mkdir ~/Downloads
cd ~/Downloads

rm -rf neovim
git clone --depth 1 --branch stable https://github.com/neovim/neovim.git 
cd neovim
make CMAKE_BUILD_TYPE=Release
sudo make install
cd ..

rm -rf tmux
git clone --depth 1 --branch 3.4 https://github.com/tmux/tmux.git
cd tmux
sh autogen.sh
./configure && make
sudo make install
cd ..

rm -rf fish-shell
git clone --depth 1 --branch 3.7.1 https://github.com/fish-shell/fish-shell.git
cd fish-shell
mkdir build
cd build
cmake ..
make
sudo make install
cd ../..

rm -rf alacritty
git clone --depth 1 --branch v0.13.2 https://github.com/alacritty/alacritty.git
cd alacritty
sudo tic -xe alacritty,alacritty-direct extra/alacritty.info
# cargo build --release --no-default-features --features=wayland
# sudo cp target/release/alacritty /usr/local/bin # or anywhere else in $PATH
# sudo cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg
# sudo desktop-file-install extra/linux/Alacritty.desktop
# sudo update-desktop-database
cd ..

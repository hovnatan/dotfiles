#!/bin/bash

cd ~

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/.tmux.conf .tmux.conf
rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm 

rm -rf ~/.config/redshift.conf
ln -s ~/.dotfiles/redshift.conf ~/.config/redshift.conf

rm -rf ~/.config/nvim
ln -s ~/.dotfiles/nvim/ ~/.config/nvim
mkdir -p ~/.vimundo/
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
nvim -c 'PlugInstall | qa'

rm -rf ~/.config/fish
ln -s ~/.dotfiles/fish/ ~/.config/fish
chsh -s `which fish`

rm -rf ~/.config/mpv
ln -s ~/.dotfiles/mpv/ ~/.config/mpv

rm -rf ~/.gitconfig
cp ~/.dotfiles/.gitconfig ~/

mkdir -p ~/opt
cd ~/opt
git clone https://github.com/junegunn/fzf.git
cd fzf
make
make install
sudo ln -s ~/opt/fzf/bin/fzf-tmux /usr/local/bin/fzf-tmux
sudo ln -s ~/opt/fzf/bin/fzf /usr/local/bin/fzf


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
mkdir -p ~/.config/nvim/autoload ~/.config/nvim/bundle && \
curl -LSso ~/.config/nvim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
cd ~/.config/nvim
git clone https://github.com/kien/ctrlp.vim.git bundle/ctrlp.vim

rm -rf ~/.config/fish
ln -s ~/.dotfiles/fish/ ~/.config/fish

rm -rf ~/.config/mpv
ln -s ~/.dotfiles/mpv/ ~/.config/mpv

rm -rf ~/.gitconfig
cp ~/.dotfiles/.gitconfig ~/

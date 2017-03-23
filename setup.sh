#!/bin/bash

cd ~

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/.tmux.conf .tmux.conf

rm -rf ~/.config/redshift.conf
ln -s ~/.dotfiles/redshift.conf ~/.config/redshift.conf

rm -rf ~/.config/nvim
ln -s ~/.dotfiles/nvim/ ~/.config/nvim
mkdir -p ~/.vimundo/

rm -rf ~/.config/fish
ln -s ~/.dotfiles/fish/ ~/.config/fish

rm -rf ~/.config/mpv
ln -s ~/.dotfiles/mpv/ ~/.config/mpv

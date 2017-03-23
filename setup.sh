#!/bin/bash

cd ~
ln -s ~/.dotfiles/.tmux.conf .tmux.conf
ln -s ~/.dotfiles/redshift.conf ~/.config/redshift.conf
ln -s ~/.dotfiles/nvim/ ~/.config/nvim
mkdir -p ~/.vimundo/
ln -s ~/.dotfiles/fish/ ~/.config/fish

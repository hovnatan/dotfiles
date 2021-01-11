#!/bin/bash

# tic -x -o $HOME/.terminfo tmux.terminfo
# tic -x -o $HOME/.terminfo termite.terminfo
tic -xe alacritty,alacritty-direct alacritty.info

# compile latest ncurses with
# ./configure --prefix=/home/hovnatan/opt
# make
# make install
# then cp ~/opt/.../tmux-256color ~/.terminfo/t/

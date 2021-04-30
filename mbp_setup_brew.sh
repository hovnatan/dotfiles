#!/bin/bash

$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)


brew update

brew install llvm bear fzf fd ripgrep neovim gtk+3 nodejs tmux fish


/usr/local/opt/ncurses/bin/infocmp tmux-256color > ~/tmux-256color.info
tic -xe tmux-256color tmux-256color.info


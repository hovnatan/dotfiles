#!/bin/bash

set -e

# $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

brew update

brew install llvm bear fzf fd ripgrep neovim gtk+3 nodejs tmux fish wget less coreutils diffutils git bash gawk man-db dust bat graphviz htop conan git-lfs bazel rustup-init go pyright findutils git-delta
brew install --cask cmake alacritty time-out
brew install rga pandoc poppler tesseract ffmpeg

brew install zathura-pdf-poppler
brew install girara --HEAD
brew install zathura --HEAD
mkdir -p $(brew --prefix zathura)/lib/zathura
ln -sf $(brew --prefix zathura-pdf-poppler)/libpdf-poppler.dylib $(brew --prefix zathura)/lib/zathura/libpdf-poppler.dylib

rustup-init
cargo install hunter

# /usr/local/opt/ncurses/bin/infocmp tmux-256color > ~/tmux-256color.info
# tic -xe tmux-256color ~/tmux-256color.info
# rm ~/tmux-256color.info

pip3 install --user pynvim ranger-fm

defaults write com.apple.screencapture disable-shadow -bool TRUE
defaults write -g ApplePressAndHoldEnabled -bool false

# to remove from quarantine
# xattr -rd com.apple.quarantine /path/to/MyApp.app

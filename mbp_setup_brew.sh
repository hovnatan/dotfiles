#!/bin/bash

set -e

# $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

brew update

brew install llvm bear fzf fd ripgrep neovim gtk+3 nodejs tmux fish ranger wget less coreutils diffutils git bash gawk man-db dust bat graphviz htop conan git-lfs bazel rustup-init go
brew install --cask cmake
brew install rga pandoc poppler tesseract ffmpeg

brew install gst-plugins-good gst-plugins-bad
rustup-init
cargo install hunter

# /usr/local/opt/ncurses/bin/infocmp tmux-256color > ~/tmux-256color.info
# tic -xe tmux-256color ~/tmux-256color.info
# rm ~/tmux-256color.info

pip3 install --user pynvim

npm install --global pyright

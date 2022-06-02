#!/bin/bash

set -e

# $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

brew update

brew install llvm bear fzf fd ripgrep neovim gtk+3 nodejs tmux fish wget less coreutils diffutils git bash gawk man-db dust bat graphviz htop conan git-lfs bazel rustup-init go pyright findutils git-delta diskonaut exa efm-langserver luarocks
brew install --cask cmake alacritty time-out zotero netron
brew install rga pandoc tesseract ffmpeg

rustup-init
cargo install difftastic stylua

# /usr/local/opt/ncurses/bin/infocmp tmux-256color > ~/tmux-256color.info
# tic -xe tmux-256color ~/tmux-256color.info
# rm ~/tmux-256color.info

pip3 install --user pynvim ranger-fm ipdb

defaults write com.apple.screencapture disable-shadow -bool TRUE
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write com.apple.Terminal FocusFollowsMouse -bool true

# to remove from quarantine
# xattr -rd com.apple.quarantine /path/to/MyApp.app

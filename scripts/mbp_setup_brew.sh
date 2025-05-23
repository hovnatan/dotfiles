#!/bin/bash

set -e

# $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

brew update

brew install llvm bear fzf fd ripgrep neovim gtk+3 nodejs tmux fish wget less coreutils diffutils git bash gawk man-db dust bat graphviz htop conan git-lfs bazel rustup-init go pyright findutils git-delta diskonaut exa efm-langserver mupdf prettier shellcheck bash-language-server stylua difftastic rga pandoc tesseract ffmpeg
brew install --cask cmake alacritty time-out zotero netron karabiner-elements alt-tab

brew tap homebrew-zathura/zathura
brew install zathura zathura-pdf-mupdf zathura-djvu
mkdir -p $(brew --prefix zathura)/lib/zathura
ln -s $(brew --prefix zathura-pdf-mupdf)/libpdf-mupdf.dylib $(brew --prefix zathura)/lib/zathura/libpdf-mupdf.dylib
ln -s $(brew --prefix zathura-djvu)/libdjvu.dylib $(brew --prefix zathura)/lib/zathura/libdjvu.dylib
rustup-init

defaults write com.apple.screencapture disable-shadow -bool TRUE
defaults write -g ApplePressAndHoldEnabled -bool false
defaults write com.apple.Terminal FocusFollowsMouse -bool true
defaults write com.apple.dock autohide-delay -float 0; killall Dock

# to remove from quarantine
# xattr -rd com.apple.quarantine /path/to/MyApp.app

cp ~/.dotfiles/.npmrc ~/.npmrc

ln -sf /Users/hovnatan/Library/CloudStorage/Dropbox/scripts/Cursor/User/settings.json ~/Library/Application\ Support/Cursor/User/settings.json
ln -sf /Users/hovnatan/Library/CloudStorage/Dropbox/scripts/Cursor/User/keybindings.json ~/Library/Application\ Support/Cursor/User/keybindings.json

ln -sf /Users/hovnatan/Library/CloudStorage/Dropbox/scripts/ssh_config ~/.ssh/local_config
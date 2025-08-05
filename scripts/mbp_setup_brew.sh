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

# needs to be tested 
# ln -s ~/.dotfiles/.zprofile_mac ~/.zprofile


# `~/.zprofile` is sourced **only when Z-shell starts a *login* shell**, which is the shell you get when you:

# • log in on a console/tty  
# • open a new terminal app that launches the shell as a login shell (common on macOS: Terminal & iTerm run `zsh -l`)  
# • connect via SSH (the remote shell is started as a login shell)  
# • run `zsh -l` explicitly

# Startup order (simplified):

# 1. `/etc/zshenv`  
# 2. `~/.zshenv`        ← always, every shell  
# —— if login shell:  
# 3. `/etc/zprofile`  
# 4. `~/.zprofile`      ← your place for login-only setup (PATH changes, env vars, locale, …)  
# —— continue if interactive:  
# 5. `/etc/zshrc`  
# 6. `~/.zshrc`         ← interactive config, aliases, key-bindings, prompts, …  
# —— after commands have run:  
# 7. `/etc/zlogin`  
# 8. `~/.zlogin`        ← end-of-login tasks (messages, tmux attach, etc.)  
# —— on logout:  
# 9. `/etc/zlogout` and `~/.zlogout` (only for login shells)

# Non-login subshells (e.g. those created by scripts or by typing `zsh` in an existing session) skip steps 3–4 and 7–9; they source only the `zshenv` files and—if interactive—the `zshrc` files.

# So: `~/.zprofile` runs **once per new login session**, before `~/.zshrc`.
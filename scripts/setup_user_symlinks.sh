#!/usr/bin/env bash

set -e

cd ~

ln -s ~/.dotfiles/.tmux.conf ~/.tmux.conf

ln -s ~/.dotfiles/.zshrc ~/.zshrc

mkdir -p ~/.vimundo/
ln -s ~/.dotfiles/.vimrc ~/.vimrc

cat <<EOT >> ~/.bashrc
if [[ -f "$HOME/.bashrc_local" ]]; then
    source "$HOME/.bashrc_local"
fi
EOT
ln -s ~/.dotfiles/.bashrc_local ~/.bashrc_local


cat <<EOT >> ~/.gitconfig
[include]
  path = ~/.dotfiles/.gitconfig_common
[user]
  name = Hovnatan Karapetyan
  email = 
EOT
vim ~/.gitconfig # add email

rm -rf ~/.config/htop
ln -s ~/.dotfiles/.config/htop ~/.config/

# cd ~
# ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519
# ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
#chmod 644 ~/.ssh/config
# touch ~/.ssh/authorized_keys
# chmod 600 ~/.ssh/authorized_keys
mkdir -p ~/.ssh
ln -s ~/.dotfiles/.ssh/config ~/.ssh/config

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_ed25519.pub into the field labeled 'Key'. with xclip -i -selection clipboard ~/.ssh/id_ed25519.pub

# cd ~/.dotfiles
# git remote set-url origin git@github.com:hovnatan/dotfiles.git

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt

# sudo gpasswd -a $USER docker
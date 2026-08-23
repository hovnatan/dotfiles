#!/usr/bin/env bash

set -e

cd ~

cp ~/.dotfiles/home/.npmrc ~/.npmrc

mkdir -p ~/.config

rm -rf ~/.config/tmux
ln -s ~/.dotfiles/home/.config/tmux ~/.config/
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
"$HOME/.config/tmux/plugins/tpm/bin/install_plugins"

rm -rf ~/.config/nvim
ln -s ~/.dotfiles/home/.config/nvim ~/.config/nvim
mkdir -p ~/.vimundo/

mkdir ~/.config/pudb
ln -s ~/.dotfiles/home/.config/pudb/pudb.cfg ~/.config/pudb/pudb.cfg
# to debug python export PYTHONBREAKPOINT=pudb.remote.set_trace then set breakpoint() in code
# to redirect port to local machine ssh -Y -L 16913:127.0.0.1:6913 192.168.4.201

rm -rf ~/.config/fish
ln -s ~/.dotfiles/home/.config/fish ~/.config/fish
fish -c 'curl -sL https://git.io/fisher | source && fisher update'

rm -rf ~/.gitconfig
cp ~/.dotfiles/home/.gitconfig ~/.gitconfig
nano ~/.gitconfig # add email

rm -rf ~/.config/htop
mkdir ~/.config/htop
ln -s ~/.dotfiles/home/.config/htoprc ~/.config/htop/htoprc

rm -rf ~/.config/feh
ln -s ~/.dotfiles/home/.config/feh ~/.config/feh

ln -s ~/.dotfiles/home/.config/ruff ~/.config/

#ln -s ~/.dotfiles/home/wc.profile ~/.local_profile

# modify ~/.config/mimeapps.list for image/tiff feh.desktop


# cd ~
# ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519
# ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
#echo -e 'Host *\nServerAliveInterval 120' >> ~/.ssh/config
#chmod 644 ~/.ssh/config
# touch ~/.ssh/authorized_keys
# chmod 600 ~/.ssh/authorized_keys
mkdir -p ~/.ssh
ln -s ~/.dotfiles/home/.ssh/config ~/.ssh/config

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_ed25519.pub into the field labeled 'Key'. with xclip -i -selection clipboard ~/.ssh/id_ed25519.pub

# cd ~/.dotfiles
# git remote set-url origin git@github.com:hovnatan/dotfiles.git

rm -rf ~/.config/ranger
ln -s ~/.dotfiles/home/.config/ranger/ ~/.config/


ln -s ~/.dotfiles/home/.condarc ~/.condarc

ln -s ~/.dotfiles/home/.config/keepassxc ~/.config/keepassxc
ln -sf ~/.dotfiles/home/.config/zathura ~/.config/
# ln -sf ~/.dotfiles/home/.config/pulse/daemon-high.conf ~/.config/pulse/daemon.conf
# ln -sf ~/.dotfiles/home/.config/pulse/client.conf ~/.config/pulse/

ln -s ~/.dotfiles/home/.config/mimeapps.list ~/.config/

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt

ln -s /usr/bin/fdfind ~/.local/bin/fd
ln -s ~/.dotfiles/home/.config/fd ~/.config/
ln -s ~/.dotfiles/home/.config/fd/ignore ~/.ignore

cp ~/.dotfiles/home/.my_colors ~/

ln -sf ~/.dotfiles/home/.config/alacritty ~/.config/

ln -sf ~/.dotfiles/home/.ctags.d ~/

# ln -s ~/.dotfiles/home/.config/fontconfig ~/.config/
# ln -sf ~/.dotfiles/home/.xinitrc ~/
# ln -sf ~/.dotfiles/home/.Xresources ~/
# ln -sf ~/.dotfiles/home/.xsessionrc ~/
# ln -sf ~/.dotfiles/home/.config/i3 ~/.config/

# sudo gpasswd -a $USER docker
# useful for docker cmds
# docker run -it --name=tuft tuft /bin/bash
# install sshd on docker, run server with service ssh start
# find out IP sudo docker inspect -f "{{ .NetworkSettings.IPAddress }}" tuft
# sshfs -o Compression=no -o Ciphers=aes128-ctr root@172.17.0.2:/deploy ~/tmp

mkdir -p ~/.conan
ln -sf ~/.dotfiles/home/.conan/profiles ~/.conan/profiles
# cmake -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCONAN_DISABLE_CHECK_COMPILER=1 ..
ln -sf ~/.dotfiles/home/.config/wezterm ~/.config/

ln -sf ~/.dotfiles/home/.config/sioyek ~/.config/

ln -sf ~/.dotfiles/home/.config/joshuto ~/.config/

ln -sf ~/.dotfiles/home/.config/atuin ~/.config/

# ln -sf ~/.dotfiles/home/.config/autostart ~/.config/

# mkdir -p ~/.local/share/applications
# cat << EOL > ~/.local/share/applications/sioyek.desktop
# [Desktop Entry]
# Name=Sioyek
# Exec=$HOME/.dotfiles/scripts/sioyek.sh %U
# Icon=$HOME/.dotfiles/home/.config/sioyek/icon1.ico
# Type=Application
# Terminal=false
# Categories=Office;Viewer
# MimeType=application/pdf;application/x-bzpdf;application/x-ext-pdf;application/x-gzpdf;application/x-xzpdf
# X-GNOME-SingleWindow=true
# EOL
# update-desktop-database ~/.local/share/applications/

sudo dpkg-reconfigure tzdata
# ps uxa | grep .vscode-server | awk '{print $2}' | xargs kill

# set the colors
~/.dotfiles/scripts/cw.sh

# cd ~/tmp
# wget https://raw.githubusercontent.com/alacritty/alacritty/master/extra/alacritty.info
# grep -vwE "Smulx" alacritty.info > alacritty_woundercurl.info
# tic -xe alacritty,alacritty-direct alacritty_woundercurl.info
# cd ~

# add to ~/.profile
# if [ -f "$HOME/.dotfiles/home/.profile_local" ] ; then
#     source "$HOME/.dotfiles/home/.profile_local"
# fi
                                                     
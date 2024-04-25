#!/usr/bin/env bash

set -e

cd ~

cp ~/.dotfiles/.npmrc ~/.npmrc

mkdir -p ~/.config

rm -rf ~/.config/tmux
ln -s ~/.dotfiles/.config/tmux ~/.config/
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
"$HOME/.config/tmux/plugins/tpm/bin/install_plugins"

rm -rf ~/.config/nvim
ln -s ~/.dotfiles/.config/nvim ~/.config/nvim
mkdir -p ~/.vimundo/

mkdir ~/.config/pudb
ln -s ~/.dotfiles/.config/pudb/pudb.cfg ~/.config/pudb/pudb.cfg
# to debug python export PYTHONBREAKPOINT=pudb.remote.set_trace then set breakpoint() in code
# to redirect port to local machine ssh -Y -L 16913:127.0.0.1:6913 192.168.4.201

rm -rf ~/.config/fish
ln -s ~/.dotfiles/.config/fish ~/.config/fish
fish -c 'curl -sL https://git.io/fisher | source && fisher update'

rm -rf ~/.gitconfig
cp ~/.dotfiles/.gitconfig ~/.gitconfig
nano ~/.gitconfig # add email

rm -rf ~/.config/htop
mkdir ~/.config/htop
ln -s ~/.dotfiles/.config/htoprc ~/.config/htop/htoprc

rm -rf ~/.config/feh
ln -s ~/.dotfiles/.config/feh ~/.config/feh

#ln -s ~/.dotfiles/wc.profile ~/.local_profile

# modify ~/.config/mimeapps.list for image/tiff feh.desktop


# cd ~
# ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519 -N '' 
# ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''
#echo -e 'Host *\nServerAliveInterval 120' >> ~/.ssh/config
#chmod 644 ~/.ssh/config
# touch ~/.ssh/authorized_keys
# chmod 600 ~/.ssh/authorized_keys

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_ed25519.pub into the field labeled 'Key'. with xclip -i -selection clipboard ~/.ssh/id_ed25519.pub

# cd ~/.dotfiles
# git remote set-url origin git@github.com:hovnatan/dotfiles.git

rm -rf ~/.config/ranger
ln -s ~/.dotfiles/.config/ranger/ ~/.config/


ln -s ~/.dotfiles/.condarc ~/.condarc

ln -s ~/.dotfiles/.config/keepassxc ~/.config/keepassxc
ln -sf ~/.dotfiles/.config/zathura ~/.config/
# ln -sf ~/.dotfiles/.config/pulse/daemon-high.conf ~/.config/pulse/daemon.conf
# ln -sf ~/.dotfiles/.config/pulse/client.conf ~/.config/pulse/

ln -s ~/.dotfiles/.config/mimeapps.list ~/.config/

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt
# for sshfs sshfs -o Compression=no,reconnect home.server.com:/ ~/home_server/ -p 22

ln -s /usr/bin/fdfind ~/.dotfiles/bin/fd
ln -s ~/.dotfiles/.config/fd ~/.config/
ln -s ~/.dotfiles/.config/fd/ignore ~/.ignore

cp ~/.dotfiles/.my_colors ~/

ln -sf ~/.dotfiles/.config/alacritty ~/.config/

ln -sf ~/.dotfiles/.config/bat ~/.config/

mkdir -p ~/.config/Code/User
ln -sf ~/.dotfiles/.config/Code/User/settings.json ~/.config/Code/User/
ln -sf ~/.dotfiles/.config/Code/User/keybindings.json ~/.config/Code/User/

ln -sf ~/.dotfiles/.ctags.d ~/

# ln -s ~/.dotfiles/.config/fontconfig ~/.config/
# ln -sf ~/.dotfiles/.xinitrc ~/
# ln -sf ~/.dotfiles/.Xresources ~/
# ln -sf ~/.dotfiles/.xsessionrc ~/
# ln -sf ~/.dotfiles/.config/i3 ~/.config/

# sudo gpasswd -a $USER docker
# useful for docker cmds
# docker run -it --name=tuft tuft /bin/bash
# install sshd on docker, run server with service ssh start
# find out IP sudo docker inspect -f "{{ .NetworkSettings.IPAddress }}" tuft
# sshfs -o Compression=no -o Ciphers=aes128-ctr root@172.17.0.2:/deploy ~/tmp

# cd ~/.dotfiles
# python3 -m venv venv_python_neovim
# source ~/.dotfiles/venv_python_neovim/bin/activate
mkdir -p ~/.conan
ln -sf ~/.dotfiles/.conan/profiles ~/.conan/profiles
# cmake -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCONAN_DISABLE_CHECK_COMPILER=1 ..
ln -sf ~/.dotfiles/.config/wezterm ~/.config/

ln -sf ~/.dotfiles/.config/sioyek ~/.config/

ln -sf ~/.dotfiles/.config/joshuto ~/.config/

ln -sf ~/.dotfiles/.config/atuin ~/.config/

# ln -sf ~/.dotfiles/.config/autostart ~/.config/

# ln -sf ~/.dotfiles/.local/share/applications/zotero.desktop ~/.local/share/applications/
# ln -sf ~/.dotfiles/.local/share/applications/sioyek.desktop ~/.local/share/applications/
# update-desktop-database ~/.local/share/applications/

sudo dpkg-reconfigure tzdata
# ps uxa | grep .vscode-server | awk '{print $2}' | xargs kill

# set the colors
~/.dotfiles/bin/cw.sh

# cd ~/tmp
# wget https://raw.githubusercontent.com/alacritty/alacritty/master/extra/alacritty.info
# grep -vwE "Smulx" alacritty.info > alacritty_woundercurl.info
# tic -xe alacritty,alacritty-direct alacritty_woundercurl.info
# cd ~

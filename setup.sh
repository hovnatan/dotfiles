#!/bin/bash

set -e

cd ~

mkdir -p ~/.config

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/.tmux.conf .tmux.conf
rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
"$HOME/.tmux/plugins/tpm/bin/install_plugins"

rm -rf ~/.config/nvim
ln -s ~/.dotfiles/.config/nvim ~/.config/nvim
mkdir -p ~/.vimundo/
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
nvim -c 'PlugInstall | qa'

mkdir ~/.config/pudb
ln -s ~/.dotfiles/.config/pudb/pudb.cfg ~/.config/pudb/pudb.cfg
# to debug python export PYTHONBREAKPOINT=pudb.remote.set_trace then set breakpoint() in code
# to redirect port to local machine ssh -Y -L 16913:127.0.0.1:6913 192.168.4.201

rm -rf ~/.config/fish
ln -s ~/.dotfiles/.config/fish ~/.config/fish
curl https://git.io/fisher --create-dirs -sLo ~/.config/fish/functions/fisher.fish
fish -c fisher

rm -rf ~/.gitconfig
cp ~/.dotfiles/.gitconfig ~/
nvim ~/.gitconfig

rm -rf ~/.config/htop
mkdir ~/.config/htop
ln -s ~/.dotfiles/.config/htoprc ~/.config/htop/htoprc

rm -rf ~/.config/feh
ln -s ~/.dotfiles/.config/feh ~/.config/feh

ln -sf ~/.dotfiles/.profile ~/.profile
#ln -s ~/.dotfiles/wc.profile ~/.local_profile

# modify ~/.config/mimeapps.list for image/tiff feh.desktop


cd ~
ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519
#echo -e 'Host *\nServerAliveInterval 120' >> ~/.ssh/config
#chmod 644 ~/.ssh/config
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_ed25519.pub into the field labeled 'Key'. with xclip -i -selection clipboard ~/.ssh/id_ed25519.pub

# cd ~/.dotfiles
# git remote set-url origin git@github.com:hovnatan/dotfiles.git

rm -rf ~/.config/ranger
ln -s ~/.dotfiles/.config/ranger/ ~/.config/


ln -s ~/.dotfiles/.condarc ~/.condarc

ln -s ~/.dotfiles/.config/keepassxc ~/.config/keepassxc
ln -sf ~/.dotfiles/.config/zathura ~/.config/
ln -sf ~/.dotfiles/.config/pulse/daemon-high.conf ~/.config/pulse/daemon.conf
ln -sf ~/.dotfiles/.config/pulse/client.conf ~/.config/pulse/


ln -s ~/.dotfiles/.ssh/config ~/.ssh/config

ln -s ~/.dotfiles/.config/mimeapps.list ~/.config/

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt
# for sshfs sshfs -o Compression=no,reconnect home.server.com:/ ~/home_server/ -p 22

ln -s /usr/bin/fdfind ~/.dotfiles/bin/fd

cp ~/.dotfiles/.my_colors ~/
ln -sf ~/.dotfiles/.config/kitty ~/.config/
ln -sf ~/.dotfiles/.bashrc ~/
ln -sf ~/.dotfiles/.bash_profile ~/

ln -s ~/.dotfiles/.config/alacritty ~/.config/

mkdir -p ~/.config/Code/User
ln -s ~/.dotfiles/.config/Code/User/settings.json ~/.config/Code/User/

# ln -s ~/.dotfiles/.config/fontconfig ~/.config/
# ln -sf ~/.dotfiles/.xinitrc ~/
# ln -sf ~/.dotfiles/.Xresources ~/
ln -sf ~/.dotfiles/.xsessionrc ~/
# ln -sf ~/.dotfiles/.config/i3 ~/.config/

# sudo gpasswd -a $USER docker
# useful for docker cmds
# docker run -it --name=tuft tuft /bin/bash
# install sshd on docker, run server with service ssh start
# find out IP sudo docker inspect -f "{{ .NetworkSettings.IPAddress }}" tuft
# sshfs -o Compression=no -o Ciphers=aes128-ctr root@172.17.0.2:/deploy ~/tmp

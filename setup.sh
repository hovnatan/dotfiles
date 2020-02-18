#!/bin/bash

set -e

cd ~

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
sudo chsh -s `which fish` $USER
wget https://raw.githubusercontent.com/junegunn/fzf/master/shell/key-bindings.fish -O ~/.config/fish/functions/fzf_key_bindings.fish

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

<<<<<<< HEAD
ln -s ~/.dotfiles/.ideavimrc ~/.ideavimrc

mkdir -p ~/Documents/MATLAB
ln -s ~/.dotfiles/Documents/MATLAB/startup.m ~/Documents/MATLAB/startup.m

mkdir -p ~/.config/gtk-3.0
rm -rf  ~/.config/gtk-3.0/settings.ini
ln -s ~/.dotfiles/.config/gtk-3.0/settings.ini  ~/.config/gtk-3.0/settings.ini
ln -s ~/.dotfiles/.config/gtk-3.0/gtk.css  ~/.config/gtk-3.0/gtk.css
ln -s ~/Dropbox/scripts/gtk_bookmarks ~/.config/gtk-3.0/bookmarks
ln -s ~/.dotfiles/.gtkrc-2.0 ~/.gtkrc-2.0
ln -sf ~/.dotfiles/.config/gtk-2.0 ~/.config/

rm -rf ~/.config/fontconfig/fonts.conf
mkdir -p ~/.config/fontconfig
ln -s ~/.dotfiles/.config/fontconfig/fonts.conf ~/.config/fontconfig/fonts.conf

rm -rf ~/.config/dunst/dunstrc
mkdir -p ~/.config/dunst
ln -s ~/.dotfiles/.config/dunst/dunstrc  ~/.config/dunst/dunstrc

ln -s ~/.dotfiles/.config/libinput-gestures.conf ~/.config

ln -sf ~/.dotfiles/.config/clipster ~/.config/
ln -sf ~/.dotfiles/.xinitrc  ~/.xinitrc

=======
>>>>>>> cleanup
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

<<<<<<< HEAD
ln -s ~/.dotfiles/.config/sway ~/.config/sway
ln -s ~/.dotfiles/.Xdefaults ~/.Xresources

ln -s /usr/bin/google-chrome-stable ~/.dotfiles/bin/chromium
ln -sf ~/.dotfiles/.config/chrome-flags.conf ~/.config/
#ln -sf ~/.dotfiles/.config/chromium-flags.conf ~/.config/

ln -s ~/.dotfiles/.condarc ~/.condarc

ln -s ~/.dotfiles/.config/keepassxc ~/.config/keepassxc

#for printer discovery
#sudo systemctl start avahi-daemon.service
#for printing
#sudo systemctl start org.cups.cupsd.service
#then visit http://localhost:631 to add printer

mkdir -p ~/.config/pulse
ln -sf ~/.dotfiles/.config/pulse/daemon-low.conf ~/.config/pulse/daemon.conf
ln -s ~/.dotfiles/.config/pulse/default.pa ~/.config/pulse/
ln -s ~/.dotfiles/.config/pulse/client.conf ~/.config/pulse/
ln -sf ~/.dotfiles/.config/pulse/equalizerrc ~/.config/pulse/
# less /proc/asound/card0/pcm0p/sub0/hw_params

rm -rf ~/.config/yay
ln -s ~/.dotfiles/.config/yay ~/.config/yay

rm -rf ~/.config/zathura
ln -s ~/.dotfiles/.config/zathura ~/.config/zathura

rm -rf ~/.config/kitty
ln -s ~/.dotfiles/.config/kitty ~/.config/kitty

ln -sf ~/.dotfiles/.config/alacritty ~/.config/

=======
ln -s ~/.dotfiles/.condarc ~/.condarc

>>>>>>> cleanup
ln -s ~/.dotfiles/.ssh/config ~/.ssh/config

ln -s ~/.dotfiles/.config/mimeapps.list ~/.config/

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt
# for sshfs sshfs -o Compression=no,reconnect home.server.com:/ ~/home_server/ -p 22

sudo gpasswd -a $USER docker

# useful for docker cmds
# docker run -it --name=tuft -v ~/doker:/deploy/host tuft /bin/bash
# rsync -a dir1/ dir2

#!/bin/bash

set -e

cd ~

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/.tmux.conf .tmux.conf
rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
"$HOME/.tmux/plugins/tpm/bin/install_plugins"

rm -rf ~/.config/redshift.conf
ln -s ~/.dotfiles/.config/redshift.conf ~/.config/redshift.conf

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
chsh -s `which fish`

rm -rf ~/.config/mpv
ln -s ~/.dotfiles/.config/mpv ~/.config/mpv

rm -rf ~/.gitconfig
cp ~/.dotfiles/.gitconfig ~/
nvim ~/.gitconfig

rm -rf ~/.workrave
mkdir -p ~/.workrave/
ln -s ~/.dotfiles/.workrave/workrave.ini ~/.workrave/workrave.ini

rm -rf ~/.config/htop
mkdir ~/.config/htop
ln -s ~/.dotfiles/.config/htoprc ~/.config/htop/htoprc

rm -rf ~/.config/feh
ln -s ~/.dotfiles/.config/feh ~/.config/feh

rm -rf ~/.config/i3
ln -s ~/.dotfiles/.config/i3 ~/.config/i3
rm -rf ~/.config/i3blocks
ln -s ~/.dotfiles/.config/i3blocks ~/.config/



rm -rf ~/.config/termite/
ln -s ~/.dotfiles/.config/termite ~/.config/
# mkdir ~/.terminfo
# cd ~/.terminfo
# wget https://raw.githubusercontent.com/thestinger/termite/master/termite.terminfo
# cd ~

rm -rf ~/.config/rofi/
ln -s ~/.dotfiles/.config/rofi ~/.config/rofi

ln -sf ~/.dotfiles/.profile ~/.profile
#ln -s ~/.dotfiles/wc.profile ~/.local_profile

# ln -s ~/.dotfiles/2e98525f-68b2-4efb-b129-042af121bfca.desktop ~/.local/share/file-manager/actions/2e98525f-68b2-4efb-b129-042af121bfca.desktop

# modify ~/.config/mimeapps.list for image/tiff feh.desktop

ln -s ~/.dotfiles/.ideavimrc ~/.ideavimrc

mkdir -p ~/Documents/MATLAB
ln -s ~/.dotfiles/Documents/MATLAB/startup.m ~/Documents/MATLAB/startup.m

mkdir -p ~/.config/gtk-3.0
rm -rf  ~/.config/gtk-3.0/settings.ini
ln -s ~/.dotfiles/.config/gtk-3.0/settings.ini  ~/.config/gtk-3.0/settings.ini
ln -s ~/.dotfiles/.config/gtk-3.0/gtk.css  ~/.config/gtk-3.0/gtk.css
ln -s ~/Dropbox/scripts/gtk_bookmarks ~/.config/gtk-3.0/bookmarks
ln -s ~/.dotfiles/.gtkrc-2.0 ~/.gtkrc-2.0

rm -rf ~/.config/fontconfig/fonts.conf
mkdir -p ~/.config/fontconfig
ln -s ~/.dotfiles/.config/fontconfig/fonts.conf ~/.config/fontconfig/fonts.conf

rm -rf ~/.config/dunst/dunstrc
mkdir -p ~/.config/dunst
ln -s ~/.dotfiles/.config/dunst/dunstrc  ~/.config/dunst/dunstrc

ln -s ~/.dotfiles/.config/libinput-gestures.conf ~/.config

ln -sf ~/.dotfiles/.config/clipster ~/.config/
ln -sf ~/.dotfiles/.xinitrc  ~/.xinitrc

cd ~
ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/id_ed25519
#echo -e 'Host *\nServerAliveInterval 120' >> ~/.ssh/config
#chmod 644 ~/.ssh/config
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_ed25519.pub into the field labeled 'Key'. with xclip -i -selection clipboard ~/.ssh/id_ed25519.pub

cd ~/.dotfiles
git remote set-url origin git@github.com:hovnatan/dotfiles.git

ln -sf ~/.dotfiles/.config/qt5ct ~/.config/

#cp ~/.dotfiles/90-touchpad.conf /etc/X11/xorg.conf.d/90-touchpad.conf
sudo gpasswd -a $USER lp
sudo gpasswd -a $USER input
sudo gpasswd -a $USER docker

mkdir -p ~/.local/share/applications
for filename in ~/.dotfiles/.local/share/applications/*.desktop; do
    [ -e "$filename" ] || continue
    basename=$(basename "$filename")
    ln -sf $filename ~/.local/share/applications/$basename
done

cd ~/.dotfiles/issue
./create_new_issue.sh
cd ~

mkdir -p ~/.local/share/themes
ln -sf ~/.dotfiles/.local/share/themes/oomox-gruvmox-dark-medium-aqua/ ~/.local/share/themes/
cd ~/.local/share/themes
git clone https://github.com/salimundo/Pop-gruvbox.git
cd ~

#gruvbox theme
#yay -S oomox
#git clone https://github.com/Yethiel/gruvmox-colors.git
#cp -R gruvmox-colors/gruvmox/ ~/.config/oomox/colors/
cd ~/.dotfiles
git update-index --assume-unchanged .workrave/workrave.ini
# git update-index --no-assume-unchanged .workrave/workrave.ini
ln -s ~/.dotfiles/.xbindkeysrc ~/

rm -rf ~/.config/ranger
ln -s ~/.dotfiles/.config/ranger ~/.config/
mkdir -p ~/.local/share/ranger
ln -s ~/Dropbox/scripts/ranger/bookmarks ~/.local/share/ranger/

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

ln -s ~/.dotfiles/.ssh/config ~/.ssh/config

ln -s ~/.dotfiles/.config/mimeapps.list ~/.config/

mkdir -p ~/tmp
mkdir -p ~/Downloads
mkdir -p ~/opt

#for running iso executables with root uncomment allow_other in /etc/fuse.conf then run e.g.,
# fuseiso xxx.iso ~/iso -o allow_other

# font debugging
# env FC_DEBUG=4 pango-view --font=monospace -t xyz | grep famil

# for chromecast from chromium enable chrome://flags/#load-media-router-component-extension

# for sshfs sshfs -o Compression=no,reconnect home.server.com:/ ~/home_server/ -p 22

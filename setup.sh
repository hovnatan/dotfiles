#!/bin/bash

cd ~

rm -rf ~/.tmux.conf
ln -s ~/.dotfiles/.tmux.conf .tmux.conf
rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

rm -rf ~/.config/redshift.conf
ln -s ~/.dotfiles/.config/redshift.conf ~/.config/redshift.conf

rm -rf ~/.config/nvim
ln -s ~/.dotfiles/.config/nvim ~/.config/nvim
mkdir -p ~/.vimundo/
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
nvim -c 'PlugInstall | qa'
ln -s ~/Dropbox/scripts/view/ ~/.local/share/nvim/view
ln -s ~/.dotfiles/.config/TabNine/ ~/.config/

rm -rf ~/.config/fish
ln -s ~/.dotfiles/.config/fish ~/.config/fish
wget https://raw.githubusercontent.com/edc/bass/master/functions/__bass.py -P ~/.config/fish/functions/
wget https://raw.githubusercontent.com/edc/bass/master/functions/bass.fish -P ~/.config/fish/functions/
chsh -s `which fish`

rm -rf ~/.config/mpv
ln -s ~/.dotfiles/.config/mpv ~/.config/mpv
ln -s ~/Dropbox/scripts/mpv/watch_later/ ~/.config/mpv/
wget https://gist.githubusercontent.com/Hakkin/5489e511bd6c8068a0fc09304c9c5a82/raw/7a19f7cdb6dd0b1c6878b41e13b244e2503c15fc/autosave.lua -P ~/.config/mpv/scripts/
wget https://raw.githubusercontent.com/vayan/autosub-mpv/master/autosub.lua -P ~/.config/mpv/scripts/
wget https://raw.githubusercontent.com/mpv-player/mpv/master/TOOLS/lua/autoload.lua -P ~/.config/mpv/scripts/
xdg-mime default mpv.desktop 'video/x-m4v' 'video/x-matroska' 'video/x-msvideo'

rm -rf ~/.gitconfig
cp ~/.dotfiles/.gitconfig ~/
nvim ~/.gitconfig

rm -rf ~/.workrave
mkdir -p ~/.workrave/
ln -s ~/.dotfiles/workrave.ini ~/.workrave/workrave.ini

rm -rf ~/.config/htop
mkdir ~/.config/htop
ln -s ~/.dotfiles/.config/htoprc ~/.config/htop/htoprc

rm -rf ~/.config/feh
ln -s ~/.dotfiles/.config/feh ~/.config/feh
xdg-mime default feh.desktop 'image/tiff' 'image/jpeg' 'image/png'

rm -rf ~/.config/i3
ln -s ~/.dotfiles/.config/i3 ~/.config/i3
rm -rf ~/.config/i3blocks
ln -s ~/.dotfiles/.config/i3blocks/ ~/.config/i3blocks
#rm -rf ~/.config/i3status
#ln -s ~/.dotfiles/.config/i3status ~/.config/i3status

rm -rf ~/.local/share/zathura/bookmarks
rm -rf ~/.local/share/zathura/history
mkdir -p ~/.local/share/zathura
ln -s ~/Dropbox/scripts/zathura/bookmarks ~/.local/share/zathura/bookmarks
ln -s ~/Dropbox/scripts/zathura/history ~/.local/share/zathura/history

xdg-mime default org.pwmt.zathura.desktop 'application/pdf'


rm -rf ~/.config/termite/
ln -s ~/.dotfiles/.config/termite ~/.config/termite
# mkdir ~/.terminfo
# cd ~/.terminfo
# wget https://raw.githubusercontent.com/thestinger/termite/master/termite.terminfo
# cd ~

rm -rf ~/.config/rofi/
ln -s ~/.dotfiles/.config/rofi ~/.config/rofi

sudo cp /home/hovnatan/.dotfiles/etc/systemd/system/wakelock.service /etc/systemd/system/wakelock.service
sudo systemctl enable /etc/systemd/system/wakelock.service
sudo mkdir -p /usr/local/share/kbd/keymaps
sudo cp ~/.dotfiles/usr/local/share/kbd/keymaps/caps_control.kmap /usr/local/share/kbd/keymaps/
sudo cp ~/.dotfiles/vconsole.conf /etc/

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

ln -sf ~/.dotfiles/.config/clipster/ ~/.config/
ln -sf ~/.dotfiles/.xinitrc  ~/.xinitrc

cd ~
ssh-keygen -t rsa
#echo -e 'Host *\nServerAliveInterval 120' >> ~/.ssh/config
#chmod 644 ~/.ssh/config

# To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_rsa.pub into the field labeled 'Key'. with xclip -i ~/.ssh/id_rsa.pub

cd ~/.dotfiles
git remote set-url origin git@github.com:hovnatan/dotfiles.git

ln -sf ~/.dotfiles/.config/qt5ct/ ~/.config/qt5ct

#cp ~/.dotfiles/90-touchpad.conf /etc/X11/xorg.conf.d/90-touchpad.conf
sudo gpasswd -a $USER lp
sudo gpasswd -a $USER input

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
#git update-index --no-assume-unchanged workrave.ini
ln -s ~/.dotfiles/.xbindkeysrc ~/

rm -rf ~/.config/ranger
ln -s ~/.dotfiles/.config/ranger/ ~/.config/ranger
rm -rf ~/.local/share/ranger
ln -s ~/Dropbox/scripts/ranger ~/.local/share/ranger

mkdir -p ~/.config/QtProject/qtcreator/styles
mkdir -p ~/.config/QtProject/qtcreator/themes
ln -s ~/.dotfiles/.config/QtProject/qtcreator/themes/gruvbox-medium.creatortheme.creatortheme ~/.config/QtProject/qtcreator/themes
ln -s ~/.dotfiles/.config/QtProject/qtcreator/themes/gruvbox-light-medium.creatortheme ~/.config/QtProject/qtcreator/themes
ln -s ~/.dotfiles/.config/QtProject/qtcreator/styles/gruvbox-dark-medium.xml ~/.config/QtProject/qtcreator/styles
ln -s ~/.dotfiles/.config/QtProject/qtcreator/styles/gruvbox-light-medium.xml ~/.config/QtProject/qtcreator/styles

ln -s ~/.dotfiles/.config/sway ~/.config/sway
ln -s .Xdefaults .Xresources

# ln -s ~/.dotfiles/.config/chromium-flags.conf ~/.config/

ln -s ~/.dotfiles/.condarc ~/.condarc

rm -rf ~/.config/mps-youtube
ln -s ~/Dropbox/scripts/mps-youtube ~/.config/mps-youtube

#for printer discovery
#sudo systemctl start avahi-daemon.service
#for printing
#sudo systemctl start org.cups.cupsd.service
#then visit http://localhost:631 to add printer

#for pulseaudio switching comment load-module module-switch-on-port-available in /etc/pulse/default.pa

#for running iso executables with root uncomment allow_other in /etc/fuse.conf then run e.g.,
# fuseiso xxx.iso ~/iso -o allow_other

# font debugging
# env FC_DEBUG=4 pango-view --font=monospace -t xyz | grep famil

# for chromecast from chromium enable chrome://flags/#load-media-router-component-extension

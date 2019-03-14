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

rm -rf ~/.config/fish
ln -s ~/.dotfiles/.config/fish ~/.config/fish
chsh -s `which fish`

rm -rf ~/.config/mpv
ln -s ~/.dotfiles/.config/mpv ~/.config/mpv
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
xdg-mime default feh.desktop 'image/tiff'

rm -rf ~/.config/i3
ln -s ~/.dotfiles/.config/i3 ~/.config/i3
rm -rf ~/.config/i3blocks
ln -s ~/.dotfiles/.config/i3blocks/ ~/.config/i3blocks
#rm -rf ~/.config/i3status
#ln -s ~/.dotfiles/.config/i3status ~/.config/i3status

rm -rf ~/.config/zathura
ln -s ~/.dotfiles/.config/zathura ~/.config/zathura
rm -rf ~/.local/share/zathura/bookmarks
ln -s ~/Dropbox/scripts/bookmarks ~/.local/share/zathura/bookmarks


rm -rf ~/.config/termite/
ln -s ~/.dotfiles/.config/termite ~/.config/termite

rm -rf ~/.config/rofi/
ln -s ~/.dotfiles/.config/rofi ~/.config/rofi

sudo ln -s /home/hovnatan/.dotfiles/wakelock.service /etc/systemd/system/wakelock.service
sudo systemctl enable /etc/systemd/system/wakelock.service

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

rm -rf ~/.config/fontconfig/fonts.conf
mkdir -p ~/.config/fontconfig
ln -s ~/.dotfiles/.config/fontconfig/fonts.conf ~/.config/fontconfig/fonts.conf

rm -rf ~/.config/dunst/dunstrc
mkdir -p ~/.config/dunst
ln -s ~/.dotfiles/.config/dunst/dunstrc  ~/.config/dunst/dunstrc

#gsettings set org.gnome.desktop.input-sources xkb-options  "['caps:ctrl_modifier', 'grp:lalt_lshift_toggle', 'grp:switch']"
#gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'us'), ('xkb', 'ru+phonetic_winkeys'), ('xkb', 'am+phonetic-alt')]"
#gsettings set org.gnome.desktop.input-sources per-window "true"
#gsettings set org.gnome.shell.app-switcher current-workspace-only true
#gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true
#gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
#gsettings set org.gnome.nautilus.preferences show-image-thumbnails 'never'
#gsettings set org.gnome.shell.extensions.dash-to-dock middle-click-action 'previews'
#gsettings set org.gnome.shell.extensions.dash-to-dock shift-click-action 'previews'
#gsettings set org.gnome.shell.extensions.dash-to-dock shift-middle-click-action 'minimize'
#gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
#gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false
#gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 600
#gsettings set org.gtk.Settings.FileChooser sort-directories-first true
#gsettings set org.freedesktop.Tracker.Miner.Files index-on-battery false
#gsettings set org.freedesktop.Tracker.Miner.Files index-on-battery-first-time false

cd ~                 #Your home directory
ssh-keygen -t rsa    #Press enter for all values
echo -e 'Host *\nServerAliveInterval 120' >> ~/.ssh/config
chmod 644 ~/.ssh/config

# echo "To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_rsa.pub into the field labeled 'Key'."

cd ~/.dotfiles
git remote set-url origin git@github.com:hovnatan/dotfiles.git

# qt5ct set to adwaitwa dark, icons too, fonts cantarell 10, dejavu sans mono 10

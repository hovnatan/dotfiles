#!/bin/bash

sudo apt update; sudo apt -y dist-upgrade

sudo apt -y install spyder3 git-cola net-tools qtcreator chrome-gnome-shell lm-sensors tmux fish python3-gdal python-gdal gdal-bin neovim libfreetype6-dev gfortran libopenblas-dev liblapack-dev tk-dev cmake qtdeclarative5-dev libtbb-dev libeigen3-dev libvtk6-dev zlib1g-dev libjpeg-dev libwebp-dev libpng-dev libtiff5-dev libopenexr-dev libdc1394-22-dev libavcodec-dev libavformat-dev libswscale-dev libtheora-dev libvorbis-dev libxvidcore-dev libx264-dev yasm libopencore-amrnb-dev libopencore-amrwb-dev libv4l-dev libxine2-dev liblapack-dev liblapacke-dev checkinstall python3-numpy python-numpy libblas-dev gfortran libatlas-base-dev libboost-all-dev ccache fonts-hack-ttf build-essential cmake pkg-config unzip workrave redshift-gtk clang-tools clang-format libgdal-dev valgrind automake python3-pip python-pip neovim curl fortune-mod fortunes htop uget vainfo mpv jupyter-notebook jupyter-core python-ipykernel python3-pandas awscli vlc ubuntu-restricted-extras feh

sudo apt -y install evolution gnome-session 
sudo apt -y install vanilla-gnome-desktop gnome-clocks
#sudo update-alternatives --config gdm3.css

gsettings set org.gnome.desktop.input-sources xkb-options  "['caps:ctrl_modifier', 'grp:lalt_lshift_toggle', 'grp:switch']"
gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'us'), ('xkb', 'ru+phonetic_winkeys'), ('xkb', 'am+phonetic-alt')]"
gsettings set org.gnome.desktop.input-sources per-window "true"
gsettings set org.gnome.shell.app-switcher current-workspace-only true
gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
gsettings set org.gnome.nautilus.preferences show-image-thumbnails 'never'
gsettings set org.gnome.shell.extensions.dash-to-dock middle-click-action 'previews'
gsettings set org.gnome.shell.extensions.dash-to-dock shift-click-action 'previews'
gsettings set org.gnome.shell.extensions.dash-to-dock shift-middle-click-action 'minimize'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 300
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
sudo cp ~/.fzf/bin/fzf /usr/local/bin/
rm -rf ~/.fzf

sudo -H pip3 install pss

wget 'https://go.skype.com/skypeforlinux-64.deb'
sudo apt -y install ./skypeforlinux-64.deb
rm skypeforlinux-64.deb

cd ~                 #Your home directory
ssh-keygen -t rsa    #Press enter for all values
# echo "To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_rsa.pub into the field labeled 'Key'."
cd ~/.dotfiles
git remote set-url origin git@github.com:hovnatan/dotfiles.git

# for Qt apps favorite on dock add to .desktop files StartupWMClass=QT...
#
# for pixel saver close button icon to work:
# cd ~/.local/share/gnome-shell/extensions/pixel-saver@deadalnix.me/themes
# mv Ambiance Ambiance.bak
# ln -s default Ambiance
# 
# to increase swap space:
# sudo swapoff -a
# sudo fallocate -l 24G /swapfile
# sudo mkswap /swapfile
# sudo swapon /swapfile

# for debug set to 0
# sudo nvim /etc/sysctl.d/10-ptrace.conf

# cp ~/.dotfiles/70-pointingstick.hwdb /lib/udev/hwdb.d/70-pointingstick.hwdb 
# sudo udevadm hwdb -u
# sudo udevadm trigger

tracker daemon -t
mkdir -p ~/.config/autostart
cd ~/.config/autostart
cp -v /etc/xdg/autostart/tracker-* ./
for FILE in `ls`; do echo Hidden=true >> $FILE; done
rm -rf ~/.cache/tracker ~/.local/share/tracker


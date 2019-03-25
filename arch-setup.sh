#!/bin/bash

grub-mkconfig -o /boot/grub/grub.cfg

sudo pacman -Sy networkmanager os-prober openssh pepper-flash qtcreator spyder3 python-numpy ipython opencv gdal python-gdal ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools cmake libva-intel-driver libva-utils intel-media-driver termius-font ttf-ubuntu-font-family ttf-hack ttf-dejavu xorg fortune-mod workrave base-devel feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub python-matplotlib glew vtk ccache boost eigen3 sudo xf86-video-intel rofi dunst vifm termite python-matplotlib zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift chromium i3-wm i3status i3lock perl-anyevent-i3 qt5ct python-gobject aws-cli unzip xautolock imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso ttf-liberation libreoffice-fresh inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wget python-scikit-learn python-scipy ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks texlive-core texlive-langextra pandoc xorg-xinit

sudo ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d
sudo ln -s /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d
#Uncomment  export FREETYPE_PROPERTIES="truetype:interpreter-version=40"
sudo nvim  /etc/profile.d/freetype2.sh
# to install dunst as notifier edit to /usr/bin/dunst 
#sudo nvim /usr/share/dbus-1/services/org.freedesktop.Notifications.service

#wget https://aur.archlinux.org/cgit/aur.git/snapshot/ttf-ms-win10.tar.gz
#tar xf ttf-ms-win10.tar.gz
#cd ttf-ms-win10
#mv ~/fonts/* .
#makepkg -Acs
#sudo pacman -U ttf-ms-win10 ttf-ms-win10-other

#for printing 
#sudo pacman -S 

#allow_others in /etc/fuse.conf
#pacman -Sy gnome gnome-weather gnome-tweaks chrome-gnome-shell gdm

sudo pip3 install pss

sudo systemctl enable tlp.service
sudo systemctl enable NetworkManager.service
systemctl --user enable pulseaudio

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

# change tar.gz to tar and specify makeflags to correct number of cores
sudo nvim /etc/makepkg.conf
yay -S skype git-cola dropbox wd719x-firmware aic94xx-firmware zoom xkblayout-state-git i3ipc-python libinput-gestures clipster xcwd-git foxitreader
sudo mkinitcpio -p linux

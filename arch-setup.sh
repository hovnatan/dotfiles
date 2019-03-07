#!/bin/bash

grub-mkconfig -o /boot/grub/grub.cfg

pacman -Sy networkmanager os-prober openssh pepper-flash qtcreator spyder3 python-numpy ipython opencv gdal python-gdal python-opencv ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp htop intel-gpu-tools cmake libva-intel-driver libva-utils intel-media-driver ttf-ubuntu-font-family ttf-hack ttf-dejavu xorg fortune-mod workrave base-devel feh mpv xclip neovim fzf tmux youtube-dl fish intel-ucode grub python-matplotlib glew vtk ccache boost eigen3 sudo xf86-video-intel davfs2 rofi dunst vifm termite python-matplotlib lightdm lightdm-gtk-greeter zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift chromium i3-wm i3status i3lock qt5ct xrandr python-gobject aws-cli unzip xautolock imagemagick scrot pulseaudio-alsa pulsemixer pulsemixer fuseiso ttf-liberation noto-fonts libreoffice-fresh inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wgetpython-scikit-learn python-scipy 


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
#sudo pacman -U ttf-ms-win10-10.0.17763.1-1-any.pkg.tar.xz

#for printing 
#sudo pacman -S sudo gpasswd -a hovnatan lp

#allow_others in /etc/fuse.conf
#pacman -Sy gnome gnome-weather gnome-tweaks chrome-gnome-shell gdm

sudo systemctl enable tlp.service
sudo systemctl enable lightdm.service
sudo systemctl enable NetworkManager.service
systemctl --user enable pulseaudio

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

cd ~
git clone https://github.com/hastinbe/i3-volume.git

yay -S skype git-cola dropbox wd719x-firmware aic94xx-firmware zoom
sudo mkinitcpio -p linux

#!/bin/bash

# sudo dd if=/dev/zero of=/swapfile bs=1024 count=8000000
# sudo chmod 0644 /swapfile
# sudo mkswap /swapfile
# sudo swapon /newswap
# sudo echo "/swapfile    swap    swap   defaults 0 0" >> /etc/fstab

sudo dnf -y remove evolution rhythmbox
sudo dnf -y install dnf-plugins-core
sudo dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf -y config-manager --add-repo http://download.opensuse.org/repositories/shells:fish:release:2/Fedora_$(rpm -E %fedora)/shells:fish:release:2.repo
sudo dnf -y copr enable heliocastro/hack-fonts ribenakid/puzzles
sudo dnf -y upgrade --refresh
sudo dnf -y install calibre htop nautilus-open-terminal transmission python3-devel git-cola qt-creator gnome-tweak-tool fuse fuse-devel libcurl-devel automake go texinfo redhat-rpm-config vdpauinfo libva-vdpau-driver libva-utils neovim tmux xclip python3-pip recoll djvulibre antiword unzip libxslt-python python-pip fortune-mod workrave redshift-gtk xorg-x11-drv-synaptics-legacy gimp java-devel flacon libevent-devel ncurses-devel ccache opencv-devel gdal-devel chrome-gnome-shell strace fzf ipython3 python3-spyder texlive gstreamer{1,}-{ffmpeg,libav,plugins-{good,ugly,bad{,-free,-nonfree}}} gstreamer{1,}-{plugin-crystalhd,ffmpeg,plugins-{good,ugly,bad{,-free,-nonfree,-freeworld,-extras}{,-extras}}} mac libmpg123 lame-libs ffmpeg freetype-freeworld dropbox mpv fish hack-fonts puzzles --setopt=strict=0

# python science libs  
# sudo pip3 install --upgrade xlrd numpy scipy pandas statsmodels scikit-learn sklearn-pandas matplotlib notebook pyqt5 spyder

# gnome setup
gsettings set org.gnome.desktop.input-sources xkb-options  "['caps:ctrl_modifier', 'grp:lalt_lshift_toggle', 'grp:switch']"
gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'us'), ('xkb', 'ru+phonetic_winkeys'), ('xkb', 'am+phonetic-alt')]"
gsettings set org.gnome.desktop.input-sources per-window "true"
gsettings set org.gnome.shell.app-switcher current-workspace-only true
gsettings set org.gnome.software download-updates false
echo "Xft.lcdfilter: lcddefault" > ~/.Xresources
gsettings "set" "org.gnome.settings-daemon.plugins.xsettings" "hinting" "slight"
gsettings "set" "org.gnome.settings-daemon.plugins.xsettings" "antialiasing" "rgba"
sudo cp -i 00-keyboard.conf /etc/X11/xorg.conf.d/
sudo cp -i 50-synaptics.conf /etc/X11/xorg.conf.d/

# disable automatic update notifications
sudo systemctl disable dnf-makecache.timer
sudo systemctl disable dnf-makecache.service

# disable tracker
mkdir -p ~/.config/autostart
cp -i trackerd.desktop ~/.config/autostart

# rc.local for trackpoint adjustment
sudo cp -i rc.local /etc/rc.d/

# passwordless github
cd ~                 #Your home directory
ssh-keygen -t rsa    #Press enter for all values
# echo "To enable passwordless github, go to settings and click 'add SSH key'. Copy the contents of your ~/.ssh/id_rsa.pub into the field labeled 'Key'."
git remote set-url origin git@github.com:hovnatan/dotfiles.git

echo "Manually install goofys (s3 fs)"

echo "To install nvidia drivers 
 1. disable noveou
 2. sudo dnf install kernel-devel xorg-x11-drv-nvidia akmod-nvidia  
 3. sudo dracut --force /boot/initramfs-$(uname -r).img $(uname -r) "

echo "Install dash to dock and pixelsaver, topicons plus and Clipboard Indicator gnome extensions. Switch from wayland to X11"

#for Matlab
#sudo rm /usr/local/MATLAB/R2017a/sys/os/glnxa64/libstd*
#sudo rm /usr/local/MATLAB/R2017a/bin/glnxa64/libfreetype.so.6
#sudo rm /usr/local/MATLAB/R2017a/bin/glnxa64/libfreetype.so.6.11.1
#sudo cp ./matlab.desktop /usr/share/applications/

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
sudo dnf -y copr enable heliocastro/hack-fonts
sudo dnf -y copr enable ribenakid/puzzles
sudo dnf install http://repo.linrunner.de/fedora/tlp/repos/releases/tlp-release.fc$(rpm -E %fedora).noarch.rpm
sudo dnf -y upgrade --refresh

sudo dnf -y install calibre htop nautilus-open-terminal transmission python3-devel git-cola qt-creator gnome-tweak-tool fuse fuse-devel libcurl-devel automake go texinfo redhat-rpm-config vdpauinfo libva-vdpau-driver libva-utils neovim tmux xclip recoll djvulibre antiword unzip fortune-mod workrave redshift-gtk xorg-x11-drv-synaptics-legacy gimp java-devel flacon libevent-devel ncurses-devel ccache gdal-devel chrome-gnome-shell strace valgrind gdb fzf texlive texlive-units gstreamer{1,}-{ffmpeg,libav,plugins-{good,ugly,bad{,-free,-nonfree}}} gstreamer{1,}-{plugin-crystalhd,ffmpeg,plugins-{good,ugly,bad{,-free,-nonfree,-freeworld,-extras}{,-extras}}} mac libmpg123 lame-libs ffmpeg freetype-freeworld dropbox mpv fish hack-fonts puzzles uget boost-static cmake-gui tlp tlp-rdw awscli pss meld clang lldb llvm-devel libcxx-devel libcxx-abi --setopt=strict=0

# for thinkpads
# sudo dnf --enablerepo=tlp-updates-testing install akmod-tp_smapi akmod-acpi_call kernel-devel

wget 'https://go.skype.com/skypeforlinux-64.rpm'
sudo dnf -y install 'skypeforlinux-64.rpm'
rm 'skypeforlinux-64.rpm'

# gnome setup
gsettings set org.gnome.desktop.input-sources xkb-options  "['caps:ctrl_modifier', 'grp:lalt_lshift_toggle', 'grp:switch']"
gsettings set org.gnome.desktop.input-sources mru-sources "[('xkb', 'us'), ('xkb', 'ru+phonetic_winkeys'), ('xkb', 'am+phonetic-alt')]"
gsettings set org.gnome.desktop.input-sources per-window "true"
gsettings set org.gnome.shell.app-switcher current-workspace-only true
gsettings set org.gnome.software download-updates false
echo "Xft.lcdfilter: lcddefault" > ~/.Xresources
gsettings "set" "org.gnome.settings-daemon.plugins.xsettings" "hinting" "slight"
gsettings "set" "org.gnome.settings-daemon.plugins.xsettings" "antialiasing" "rgba"
sudo cp -i 50-pointingdevice.conf /etc/X11/xorg.conf.d/

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

echo "Install dash to dock and pixelsaver, topicons plus, Remove Accessibility, and Clipboard Indicator gnome extensions. Switch from wayland to X11"

#for Matlab
#sudo rm /usr/local/MATLAB/R2017a/sys/os/glnxa64/libstd*
#sudo rm /usr/local/MATLAB/R2017a/bin/glnxa64/libfreetype.so.6
#sudo rm /usr/local/MATLAB/R2017a/bin/glnxa64/libfreetype.so.6.11.1
#sudo cp ./matlab.desktop /usr/share/applications/

#for system76
#sudo cp sound-headphones.conf /etc/modules-load.d/sound-headphones.conf
#sudo cp grub /etc/sysconfig/grub
#sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg

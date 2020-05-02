#!/bin/bash

# Remove keymap hook from /etc/mkinitcpio.conf HOOKS =()

rm -rf ~/.config/pacman
ln -s ~/.dotfiles/.config/pacman ~/.config/pacman

set -e

sudo systemctl enable NetworkManager.service

sudo pacman -Sy --needed linux54-acpi_call networkmanager network-manager-applet os-prober openssh pepper-flash ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp tlp-rdw htop intel-gpu-tools libva-intel-driver libva-utils intel-media-driver xorg fortune-mod feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub glew vtk xf86-video-intel rofi dunst i3-wm python-i3ipc i3status perl-anyevent-i3 qt5-styleplugins python-gobject s3fs-fuse unzip imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso hunspell-en_US lm_sensors uget transmission-cli transmission-gtk wget ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks xorg-xinit pdfgrep xbindkeys ripgrep aria2 tk libjpeg-turbo ctags time yarn w3m elinks odt2txt mediainfo highlight ffmpegthumbnailer atool luarocks tcl tk libimagequant dex fwupd vlc bash-language-server lsof rsync unrar perl-image-exiftool meld libvdpau-va-gl vulkan-intel ntp jre-openjdk unclutter xss-lock pacman-contrib libappindicator-gtk3 blueman udisks2 udiskie tldr rofimoji keepassxc ntfs-3g trayer termite rust fd manjaro-firmware upower ranger playerctl mhwd-tui base-devel chromium

sudo pacman -Sy --needed freeoffice texlive-core texlive-langextra pandoc pandoc-citeproc hplip avahi cups inkscape gimp zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift workrave

sudo pacman -Sy --needed docker

sudo pacman -Sy --needed clang llvm cmake gdb valgrind perf strace cppcheck ccache eigen3 boost

sudo pacman -Sy --needed python-pip python-sh python-language-server autopep8 python-pyperclip ipython python-pydbus python-systemd python-unidecode python-google-auth-oauthlib python-google-python-google-api-python-client

sudo pacman -Sy --needed ttf-croscore ttf-font-awesome awesome-terminal-fonts terminus-font # noto-fonts-cjk noto-fonts noto-fonts-emoji ttf-liberation

# latex language server
sudo luarocks install --server=http://luarocks.org/dev digestif

pip3 install --user pysnooper neovim-remote arxiv python-opensubtitles

sudo systemctl enable ntpd.service
sudo systemctl enable bluetooth
# sudo systemctl enable docker.service
systemctl --user enable pulseaudio

yay -Sy --needed aws-cli google-cloud-sdk

yay -S --needed freetype2-cleartype
yay -S --needed skypeforlinux-stable-bin zoom dropbox google-chrome
yay -S --needed libinput-gestures clipster i3lock-color gruvbox-icon-theme bear-git nerd-fonts-dejavu-complete
yay -S --needed dragon-drag-and-drop-git mpv-mpris-git play-with-mpv

wget 'https://www.dropbox.com/download?dl=packages/dropbox.py' -O ~/.dotfiles/bin/dropbox.py
chmod +x ~/.dotfiles/bin/dropbox.py
# yay -S --needed interception-caps2esc interception-tools
# yay -S --needed ptags ripgrep-all
# sudo grub-mkconfig -o /boot/grub/grub.cfg

# sudo nvim /etc/systemd/sleep.conf
# AllowSuspendThenHibernate=yes
# HibernateDelaySec=7200
# sudo nvim /etc/systemd/logind.conf
# HandleLidSwitch=suspend-then-hibernate
# InhibitDelayMaxSec=35

# to use last grub edit /etc/default/grub
# GRUB_SAVEDEFAULT=true
# GRUB_DEFAULT=saved
# sudo grub-mkconfig -o /boot/grub/grub.cfg

# remove orphans
# sudo pacman -Rns (pacman -Qtdq)
# remove cache
# yay -Sc

# enabel timesync
sudo systemctl enable systemd-timesyncd.service
# set timezone
# timedatectl set-timezone (curl https://ipapi.co/timezone)

# to cleanup repo
# java -jar bfg-1.13.0.jar -b 32K ~/work/repo

# sudo cp ~/.dotfiles/etc/systemd/system/wakelock.service /etc/systemd/system/wakelock.service
# sudo systemctl enable /etc/systemd/system/wakelock.service
sudo mkdir -p /usr/local/share/kbd/keymaps
sudo cp ~/.dotfiles/usr/local/share/kbd/keymaps/caps_control.kmap /usr/local/share/kbd/keymaps/
sudo cp ~/.dotfiles/etc/vconsole.conf /etc/


# terminal fun
# yay -S asciiquarium sl cmatrix

sudo systemctl enable tlp.service NetworkManager-dispatcher.service
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket

sudo cp -p ~/.dotfiles/etc/X11/xorg.conf.d/90-custom.conf /etc/X11/xorg.conf.d/
sudo cp -p ~/.dotfiles/etc/modprobe.d/i915.conf /etc/modprobe.d/

sudo mkdir -p /opt/bin
sudo cp -p ~/.dotfiles/opt/bin/disable_wake_on_usb.sh /opt/bin/
sudo cp ~/.dotfiles/etc/systemd/system/disable-USB-wakeup.service /etc/systemd/system/
sudo systemctl enable disable-USB-wakeup.service

# sudo systemctl enable fstrim.timer

# end default conf
exit 0

# sudo cp -p etc/udevmon.yaml /etc/
# sudo systemctl enable udevmon
sudo localectl --no-convert set-x11-keymap us,am pc105 ,phonetic-alt grp:alt_space_toggle,ctrl:nocaps,grp:rctrl_switch

# pacman best servers for armenia found by rankmirrors. Write in /etc/pacman.d/mirrorlist
# Server = http://mirror.metalgamer.eu/archlinux/$repo/os/$arch
# Server = http://archlinux.cu.be/$repo/os/$arch
# Server = http://arch.eckner.net/archlinux/$repo/os/$arch
# Server = http://archlinux.vi-di.fr/$repo/os/$arch
# Server = http://archlinux.mirrors.benatherton.com/$repo/os/$arch
# Server = http://mirrors.uni-plovdiv.net/archlinux/$repo/os/$arch

# for rankmirrors
# sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup
# sudo sh -c 'rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist'

# yay -S linux-clear-bin intel-ucode-clear
# sudo cp ~/.dotfiles/etc/systemd/system/usb-reset.service /etc/systemd/system/
# sudo cp ~/.dotfiles/bin/usbmodreset.sh /usr/bin/
# sudo systemctl enable usb-reset.service

cd ~/tmp
git clone https://gitlab.manjaro.org/arch-packages/extra/ffmpeg.git
cd ffmpeg/repos/extra-x86_64
makepkg -si
cd ~/tmp
rm -rf ffmpeg
git clone https://gitlab.manjaro.org/arch-packages/community/mpv.git
cd mpv/repos/community-x86_64
makepkg -si
cd ~/tmp
rm -rf mpv
git clone https://gitlab.manjaro.org/arch-packages/extra/pulseaudio.git
cd pulseaudio/repos/extra-x86_64
makepkg -si
cd ~/tmp
rm -rf pulseaudio
git clone https://gitlab.manjaro.org/arch-packages/extra/pulseaudio-alsa.git
cd pulseaudio-alsa/repos/extra-any
makepkg -si
cd ~/tmp
rm -rf pulseaudio-alsa
# Add to /etc/pacman.conf
# IgnorePkg   = mpv ffmpeg pulseaudio pulseaudio-alsa

# fwupd
fwupdmgr refresh
fwupdmgr get-updates
fwupdmgr update

# manjaro hardware setup: list devices
sudo mhwd -l -d
sudo mhwd -i pci <video-linux>etc

#!/bin/bash

# sudo nvim /etc/makepkg.conf change PKGEXT to tar.zst
# Remove keymap hook from /etc/mkinitcpio.conf HOOKS =()

set -e

sudo systemctl enable NetworkManager.service

sudo pacman -Sy --needed networkmanager network-manager-applet os-prober openssh pepper-flash ethtool lsb-release smartmontools x86_energy_perf_policy powertop tlp tlp-rdw htop intel-gpu-tools libva-intel-driver libva-utils intel-media-driver xorg fortune-mod workrave feh mpv xclip neovim python-neovim fzf tmux youtube-dl fish intel-ucode grub glew vtk xf86-video-intel rofi dunst zathura zathura-djvu zathura-ps zathura-pdf-mupdf redshift i3-wm python-i3ipc i3status perl-anyevent-i3 qt5-styleplugins python-gobject aws-cli unzip imagemagick scrot pulseaudio-alsa pulseaudio-bluetooth pulsemixer pulsemixer fuseiso inkscape gimp hunspell-en_US hplip avahi cups lm_sensors uget transmission-cli transmission-gtk wget ack pavucontrol sshfs bluez bluez-utils acpi alsa-utils sysstat i3blocks texlive-core texlive-langextra pandoc xorg-xinit pdfgrep xbindkeys ripgrep aria2 tk libjpeg-turbo ctags time yarn w3m elinks odt2txt mediainfo highlight ffmpegthumbnailer atool yapf pandoc-citeproc luarocks tcl tk libimagequant dex mps-youtube fwupd vlc bash-language-server xcape lsof rsync unrar perl-image-exiftool meld libvdpau-va-gl vulkan-intel ntp jre-openjdk unclutter xss-lock pacman-contrib libappindicator-gtk3 blueman udisks2 udiskie tldr rofimoji keepassxc ntfs-3g docker trayer termite rust freeoffice fd manjaro-firmware

sudo pacman -Sy --needed base-devel clang llvm cmake gdb valgrind perf strace cppcheck ccache eigen3 boost

sudo pacman -Sy --needed python-pip python-sh python-language-server autopep8 python-pyperclip ipython python-pydbus python-systemd python-unidecode

sudo pacman -Sy --needed ttf-croscore ttf-font-awesome awesome-terminal-fonts # noto-fonts-cjk noto-fonts noto-fonts-emoji ttf-liberation

# latex language server
sudo luarocks install --server=http://luarocks.org/dev digestif

pip3 install --user pysnooper neovim-remote arxiv python-opensubtitles

sudo systemctl enable ntpd.service
sudo systemctl enable bluetooth
# sudo systemctl enable docker.service
systemctl --user enable pulseaudio

cd ~/.dotfiles
git clone https://github.com/hovnatan/i3-volume.git

yay -S --needed freetype2-cleartype
yay -S --needed skypeforlinux-stable-bin zoom dropbox google-chrome
yay -S --needed libinput-gestures clipster i3lock-color gruvbox-icon-theme bear-git nerd-fonts-dejavu-complete
yay -S --needed dragon-drag-and-drop-git mpv-mpris-git playerctl-git ranger-git autojump play-with-mpv
yay -S --needed interception-caps2esc interception-tools
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

sudo cp -p ~/.dotfiles/etc/X11/xorg.conf.d/90-touchpad.conf /etc/X11/xorg.conf.d/
sudo cp -p ~/.dotfiles/etc/modprobe.d/i915.conf /etc/modprobe.d/

exit 0

sudo mkdir -p /opt/bin
sudo cp -p ~/.dotfiles/opt/bin/disable_wake_on_usb.sh /opt/bin/
sudo cp ~/.dotfiles/etc/systemd/system/disable-USB-wakeup.service /etc/systemd/system/
sudo systemctl enable disable-USB-wakeup.service

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

#!/usr/bin/env bash

set -e

apt-config dump | grep -we Recommends -e Suggests | sed s/1/0/ | tee /etc/apt/apt.conf.d/99norecommend
apt-get update
apt-get -y dist-upgrade
apt-get install -y software-properties-common curl gnupg wget locales sudo

locale-gen --no-purge en_US.UTF-8

apt-add-repository ppa:fish-shell/release-3
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -

add-apt-repository multiverse
add-apt-repository universe
add-apt-repository restricted


apt-get install -y jq feh fzf fd-find ripgrep fish ranger clang clangd clang-format clang-tidy bear valgrind curl htop cmake aria2 mediainfo pandoc git-lfs bat nodejs unzip golang-go sqlite3 libsqlite3-dev shellcheck gawk python3-venv yacc tmux pkg-config libssl-dev build-essential openssh-client libtool-bin gettext automake libevent-dev libncurses-dev tzdata psmisc

apt-get install -y python2 python3-pip

update-alternatives --install /usr/bin/python python /usr/bin/python2 1
update-alternatives --install /usr/bin/python python /usr/bin/python3 2
# sudo apt-get install -y wmctrl awscli docker.io default-jre xdg-utils universal-ctags poppler-utils ffmpeg libfuse2 ubuntu-drivers-common octave ppa-purge net-tools sshfs 
# if [[ "$WSL_DISTRO_NAME" ]]; then
#    sudo apt-get install wslu
# fi
# type -p curl >/dev/null || sudo apt install curl -y
# curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
#   && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
#   && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
#   && sudo apt update \
#   && sudo apt install gh -y
# sudo apt-get install -y xrdp remmina
# sudo apt-get install -y texlive-latex-recommended texlive-pictures texlive-latex-extra latexmk
# sudo apt-get install chrome-gnome-shell zathura xrdp fonts-croscore kitty
# sudo apt-get install -y i3 i3blocks
# sudo apt-get install -y mesa-utils freeglut3-dev

# sudo vim /etc/sysctl.d/10-ptrace.conf

# ubuntu-drivers devices
# sudo ubuntu-drivers autoinstall


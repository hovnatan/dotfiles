#!/usr/bin/env bash

set -e

apt-get update
apt-get -y dist-upgrade
apt-get install -y software-properties-common curl gnupg wget locales sudo htop tmux zsh vim build-essential tzdata git openssh-client python3-venv python3-pip

locale-gen --no-purge en_US.UTF-8

# update-alternatives --install /usr/bin/python python /usr/bin/python3 1
# if [[ "$WSL_DISTRO_NAME" ]]; then
#    sudo apt-get install wslu
# fi
# sudo apt-get install -y xrdp remmina

# sudo vim /etc/sysctl.d/10-ptrace.conf

# ubuntu-drivers devices
# sudo ubuntu-drivers autoinstall

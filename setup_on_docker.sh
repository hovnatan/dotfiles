#!/bin/bash

git clone --branch bare https://github.com/hovnatan/dotfiles

mv dotfiles .dotfiles
cd .dotfiles
./ubuntu_setup.sh
./setup.sh

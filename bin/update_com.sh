#!/bin/bash

if [[ "$1" != "" ]] ; then
  fish -c fisher &
fi
"$HOME/.tmux/plugins/tpm/bin/update_plugins" all &

wait

sudo apt update
sudo apt -y dist-upgrade
sudo apt -y autoremove

nvim -c PlugUpdate

source ~/miniconda3/etc/profile.d/conda.sh
conda activate
conda update -y --all

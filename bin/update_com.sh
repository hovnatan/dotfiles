#!/bin/bash

sudo apt update
sudo apt dist-upgrade

fish -c fisher

"$HOME/.tmux/plugins/tpm/bin/update_plugins" all

nvim -c PlugUpdate

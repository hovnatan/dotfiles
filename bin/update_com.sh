#!/bin/bash

"$HOME/.tmux/plugins/tpm/bin/update_plugins" all
nvim -c PlugUpdate
yay -Syu

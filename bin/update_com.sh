#!/bin/bash

fish -c fisher
"$HOME/.tmux/plugins/tpm/bin/update_plugins" all
nvim -c PlugUpdate

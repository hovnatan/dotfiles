#!/bin/bash

out=$(tmux list-sessions -F '#{?session_attached,,#{session_name}}' | sed '/^$/d' | fzf -i --reverse --header jump-to-session | cut -d ":" -f 1) 
[[ -n "$out" ]] && tmux switch-client -t "$out"

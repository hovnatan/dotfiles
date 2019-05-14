function set_display
    set --export DISPLAY (tmux show-environment DISPLAY | sed -rn 's/^DISPLAY=(.*).*/\1/p')
end

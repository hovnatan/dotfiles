function fish_right_prompt --description 'Write out the prompt'
    # The active virtualenv, then the last command's timer (config.fish,
    # __command_timer), three spaces apart, e.g. "(.venv)   3m 14.341s   13 Nov 00:18:05".
    set -l items
    if set -q VIRTUAL_ENV
        set -a items (set_color 4B8BBE)"("(basename "$VIRTUAL_ENV")")"(set_color normal)
    end
    if test -n "$__command_timer_str"
        set -a items (set_color blue)"$__command_timer_str"(set_color normal)
    end
    string join '   ' $items
end

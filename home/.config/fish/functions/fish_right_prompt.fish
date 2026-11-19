function fish_right_prompt --description 'Write out the prompt'
    # The active virtualenv, then the last command's timer (config.fish,
    # __command_timer), three spaces apart, then one space of inset, e.g.
    # "(.venv)   3m 14.341s   13 Nov 00:18:05 ".
    set -l items
    if set -q VIRTUAL_ENV
        set -a items (set_color 4B8BBE)"("(basename "$VIRTUAL_ENV")")"(set_color normal)
    end

    # The timer is a margin note, so it is quieter than the output beside it:
    # the default foreground, dimmed (SGR 2, faint). That is how Claude Code
    # prints its "Resume this session with:" line on exit, so the two read
    # alike, and it needs no colour per theme: the terminal fades whatever
    # foreground it has (Ghostty: faint-opacity, 0.5 by default, about
    # 9c957f on Gruvbox Light). It was blue until 2026-11-19, the colour of
    # ls's directories, and read as content.
    if test -n "$__command_timer_str"
        set -a items (set_color --dim)"$__command_timer_str"(set_color normal)
    end

    # Nothing to show (an empty Enter, no virtualenv): no prompt at all, not
    # a lone inset space.
    test (count $items) -gt 0; or return

    # The trailing space lines the time up with the tmux bar's clock, which
    # stops one column short of the edge (status-right ends in a space,
    # tmux.conf); without it the prompt ran one column past the clock:
    #
    #   bar      ...   19 Nov 12:01 EST |
    #   prompt   0.014s   19 Nov 11:59:20 |
    echo -n (string join '   ' $items)" "
end

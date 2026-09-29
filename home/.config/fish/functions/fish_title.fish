function fish_title
    set out ""
    if test (status current-command) = fish
        set out $PWD
    else
        set out (status current-command)
    end

    # Over ssh the tab leads with the machine, as named in the prompt, so a
    # remote tab reads "(<host>) ~/.dotfiles" or "(<host>) vim" rather than
    # passing for a local one. tmux titles do the same (~/.tmux.conf,
    # set-titles-string). Not in iTerm2, which shows the host itself
    # (iterm2_report_host).
    if set -q SSH_CONNECTION; and not is_iterm2
        set out "("(machine_name)") $out"
    end
    echo $out
end

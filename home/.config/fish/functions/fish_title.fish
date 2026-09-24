function fish_title
    set out ""
    if test (status current-command) = fish
        set out $PWD
    else
        set out (status current-command)
    end

    # Over ssh the tab leads with the machine, as named in the prompt
    # (fish_prompt_host, else the hostname up to its first dot), so a remote
    # tab reads "(<host>) ~/.dotfiles" or "(<host>) vim" rather than passing for
    # a local one. tmux titles do the same (~/.tmux.conf, set-titles-string).
    if set -q SSH_CONNECTION
        set -l host (prompt_hostname)
        set -q fish_prompt_host; and set host $fish_prompt_host
        set out "($host) $out"
    end
    echo $out
end

function fish_title
    # Idle: "fish:" and the prompt's short path, e.g. "fish:~/d/proj";
    # while a command runs, its name, e.g. "vim".
    set out ""
    if test (status current-command) = fish
        set out "fish:"(prompt_pwd)
    else
        set out (status current-command)
    end

    # Over ssh the tab leads with the machine, as named in the prompt, so a
    # remote tab reads "(<host>) fish:~/.dotfiles" or "(<host>) vim" rather than
    # passing for a local one. Not in iTerm2, whose titles name no host
    # (iterm2_report_host), and not in tmux: there this title names the
    # window in the bar, where every window is on this machine, and tmux
    # titles the terminal itself, host included (~/.config/tmux/tmux.conf,
    # set-titles-string):
    #   ssh, no tmux   "(<host>) fish:~/x"
    #   ssh, tmux      "fish:~/x"  (window "1 fish:~/x")
    if set -q SSH_CONNECTION; and not set -q TMUX; and not is_iterm2
        set out "("(machine_name)") $out"
    end
    echo $out
end

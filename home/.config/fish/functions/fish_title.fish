function fish_title
    # Idle: "fish:" and the prompt's short path, e.g. "fish:~/d/proj";
    # while a command runs, its name, e.g. "vim".
    set out ""
    if test (status current-command) = fish
        set out "fish:"(prompt_pwd)
    else
        set out (status current-command)
    end

    # The tab leads with where the shell runs: over ssh the machine, as named
    # in the prompt, else "local", so a remote tab never passes for a local
    # one: "(<host>) fish:~/.dotfiles", "(local) vim". Not in iTerm2, whose
    # titles name no host (iterm2_report_host), and not in tmux: there this
    # title names the window in the bar, where every window is on this
    # machine, and tmux titles the terminal itself, lead included
    # (~/.config/tmux/tmux.conf, set-titles-string):
    #   ssh, no tmux     "(<host>) fish:~/x"
    #   local, no tmux   "(local) fish:~/x"
    #   tmux             "fish:~/x"  (window "1 fish:~/x")
    if not set -q TMUX; and not is_iterm2
        set -l where local
        set -q SSH_CONNECTION; and set where (machine_name)
        set out "($where) $out"
    end
    echo $out
end

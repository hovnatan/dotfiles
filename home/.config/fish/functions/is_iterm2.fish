function is_iterm2 --description 'True when this shell draws straight into an iTerm2 tab, over ssh too'
    # iTerm2 exports LC_TERMINAL=iTerm2 and macOS ssh forwards LC_* (SendEnv
    # in /etc/ssh/ssh_config.d/100-macos.conf), so a remote shell sees it as
    # well. TERM_PROGRAM is iTerm.app locally and unset over ssh; any other
    # value means another terminal inherited LC_TERMINAL:
    #   iTerm2 tab, local or ssh           -> true
    #   tmux pane (TERM_PROGRAM=tmux)      -> false: tmux owns the title
    #   VS Code started from an iTerm2 shell (TERM_PROGRAM=vscode) -> false
    test "$LC_TERMINAL" = iTerm2; and contains -- "$TERM_PROGRAM" "" iTerm.app
end

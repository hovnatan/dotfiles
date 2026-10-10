function iterm2_report_host --description 'Tell iTerm2 which machine this tab runs on (OSC 1337 RemoteHost)'
    # The one place that explains and writes the iTerm2 host report. It is
    # sticky until the next one, so it is sent on every prompt and on every
    # tmux attach:
    #
    #   report        over ssh              local
    #   RemoteHost    <user>@<short host>   <user>@$hostname
    #
    # Two callers:
    #
    #   fish_prompt, outside tmux     iterm2_report_host
    #       is_iterm2 gate, ssh from $SSH_CONNECTION
    #   ~/.config/tmux/report-attach.sh, for an attaching iTerm2 client
    #       iterm2_report_host --tmux-attach=ssh|local  >client tty
    #       no gate and ssh from the flag: the hook runs in the tmux server,
    #       whose environment is not the client's, so it read the client's
    #       terminal and ssh state from tmux's session environment
    #
    # Titles carry no host in iTerm2: the Dotfiles profile's Custom Tab Title
    # and Custom Window Title
    # (home/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json)
    # are the session name alone, "~/.dotfiles", and the shells, nvim and
    # tmux leave their "(<host>) " prefix out there too, so an ssh tab reads
    # like a local one and the prompt is what names the machine. The short
    # host is machine_name, the name the prompt shows.
    #
    # The window title (Dock menu, Window menu, Cmd+`) is reached one scope
    # up, "\(currentTab.currentSession.name)": a bare currentSession in a
    # window expression renders as "". iTerm2 reads it when a window opens,
    # so a profile change reaches only windows opened after it; a window
    # restored from an arrangement keeps the title it was saved with.
    #
    # RemoteHost is how iTerm2 tells local from remote, and it must be the real
    # hostname locally, never "": an empty host is a remote one named "", and
    # Cmd+V of an image then takes the remote path ("Upload and Paste Path")
    # and fails with "Failed to connect to :22".
    argparse 'tmux-attach=' -- $argv; or return

    # Where the tab runs. A prompt reports only where the sequences reach
    # iTerm2 (is_iterm2): inside tmux they would be swallowed, and the attach
    # report covers that case.
    set -l over_ssh false
    if set -q _flag_tmux_attach
        switch $_flag_tmux_attach
            case ssh
                set over_ssh true
            case local
            case '*'
                echo "iterm2_report_host: --tmux-attach takes ssh or local, not '$_flag_tmux_attach'" >&2
                return 2
        end
    else
        is_iterm2; or return 0
        set -q SSH_CONNECTION; and set over_ssh true
    end

    set -l name (machine_name)
    or begin
        echo "iterm2_report_host: machine_name found no name (\$hostname is '$hostname')" >&2
        return 1
    end
    set -l remote_host "$USER@$hostname"
    $over_ssh; and set remote_host "$USER@$name"
    printf '\e]1337;RemoteHost=%s\a' $remote_host
end

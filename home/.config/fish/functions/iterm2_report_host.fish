function iterm2_report_host --description 'Tell iTerm2 which machine this tab runs on and whether tmux owns it (OSC 1337 RemoteHost, host_tag, in_tmux)'
    # The one place that explains and writes the iTerm2 tab reports. All
    # three are sticky until the next one, so they are sent on every prompt
    # and on every tmux attach:
    #
    #   report                  over ssh              local
    #   RemoteHost              <user>@<short host>   <user>@$hostname
    #   SetUserVar host_tag     "(<short host>) "     "(<short host>) "
    #   SetUserVar in_tmux      0 prompt, 1 attach    0 prompt, 1 attach
    #
    # Two callers:
    #
    #   fish_prompt, outside tmux     iterm2_report_host
    #       is_iterm2 gate, ssh from $SSH_CONNECTION, in_tmux 0
    #   ~/.config/tmux/report-attach.sh, for an attaching iTerm2 client
    #       iterm2_report_host --tmux-attach=ssh|local  >client tty
    #       no gate and ssh from the flag: the hook runs in the tmux server,
    #       whose environment is not the client's, so it read the client's
    #       terminal and ssh state from tmux's session environment; in_tmux 1
    #
    # host_tag is the title. The Dotfiles profile's Custom Tab Title
    # (home/Library/Application Support/iTerm2/DynamicProfiles/dotfiles.json)
    # is "\(currentSession.user.host_tag?)\(currentSession.name)", so a tab
    # reads "(mbp) ~/.dotfiles", and "(mbp) Claude Code" once a program
    # retitles it: iTerm2 prepends the tag, so no retitle drops it. The short
    # host is machine_name, the name the prompt shows. The tag goes first
    # because only the end of a long title is ever cut
    # (TabTitlesUseSmartTruncation off, scripts/setup_user_symlinks.sh);
    # iTerm2 has no setting that always cuts the start.
    #
    # RemoteHost is how iTerm2 tells local from remote, and it must be the real
    # hostname locally, never "": an empty host is a remote one named "", and
    # Cmd+V of an image then takes the remote path ("Upload and Paste Path")
    # and fails with "Failed to connect to :22".
    #
    # in_tmux says whether a tmux client owns the tab, so it is 1 from attach
    # until a prompt outside tmux comes back (detach, exit, a dropped ssh).
    # The Ctrl-U / Ctrl-D scroll keys (~/.hammerspoon/iterm2_keys.lua) leave
    # the keys to tmux while it is 1.
    argparse 'tmux-attach=' -- $argv; or return

    # Where the tab runs and who owns it. A prompt reports only where the
    # sequences reach iTerm2 (is_iterm2): inside tmux they would be swallowed,
    # and the attach report covers that case.
    set -l over_ssh false
    set -l in_tmux
    if set -q _flag_tmux_attach
        switch $_flag_tmux_attach
            case ssh
                set over_ssh true
            case local
            case '*'
                echo "iterm2_report_host: --tmux-attach takes ssh or local, not '$_flag_tmux_attach'" >&2
                return 2
        end
        set in_tmux MQ== # base64 "1"
    else
        is_iterm2; or return 0
        set -q SSH_CONNECTION; and set over_ssh true
        set in_tmux MA== # base64 "0"
    end

    set -l name (machine_name)
    or begin
        echo "iterm2_report_host: machine_name found no name (\$hostname is '$hostname')" >&2
        return 1
    end
    set -l remote_host "$USER@$hostname"
    $over_ssh; and set remote_host "$USER@$name"
    set -l host_tag (printf '(%s) ' $name | base64)
    printf '\e]1337;RemoteHost=%s\a\e]1337;SetUserVar=host_tag=%s\a\e]1337;SetUserVar=in_tmux=%s\a' \
        $remote_host "$host_tag" $in_tmux
end

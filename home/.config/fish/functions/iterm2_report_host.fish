function iterm2_report_host --description 'Tell iTerm2 which machine this prompt runs on (OSC 1337 RemoteHost + host_tag)'
    # The one place that explains the iTerm2 tab host. Two reports, both
    # sticky until the next one, so fish_prompt sends them on every prompt:
    #
    #   report                  over ssh              local
    #   RemoteHost              <user>@<short host>   <user>@$hostname
    #   SetUserVar host_tag     "(<short host>) "     "(<short host>) "
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
    # Only where the sequences reach iTerm2 (is_iterm2): inside tmux they would
    # be swallowed; ~/.config/tmux/ssh-title-flag.sh reports for tmux clients.
    is_iterm2; or return 0
    set -l name (machine_name)
    set -l remote_host "$USER@$hostname"
    set -q SSH_CONNECTION; and set remote_host "$USER@$name"
    set -l host_tag (printf '(%s) ' $name | base64)
    printf '\e]1337;RemoteHost=%s\a\e]1337;SetUserVar=host_tag=%s\a' $remote_host "$host_tag"
end

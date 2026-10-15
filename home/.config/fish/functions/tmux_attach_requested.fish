function tmux_attach_requested --description 'Replace this login shell with the tmux attach that LC_TMUX_ATTACH asks for'
    # A saved iTerm2 ssh arrangement reattaches a remote tmux session as a
    # plain login carrying the request in the environment, not as a remote
    # command (scripts/lib/iterm2_ssh_arrangement.py, attach_line):
    #
    #   Mac tab: LC_TMUX_ATTACH=claude:ai-agent ssh -o SendEnv=LC_TMUX_ATTACH vm
    #     -> sshd / tailscaled: no command, so login(1), pty is the user's
    #     -> bash -> fish --login (from_bash_login.sh) -> config.fish
    #     -> here: exec tmux -L claude attach -t =ai-agent
    #
    # Over Tailscale SSH a remote command (`ssh -t vm tmux attach ...`) skips
    # login(1) and the pty stays root's, so the client-attached hook
    # (~/.config/tmux/report-attach.sh) cannot write the iTerm2 host report
    # to it. The value is <socket>:<session>; the socket is one of the
    # arrangement's SOCKETS, "default" for tmux's own; tmux allows no ":" in
    # a session name, so the first ":" splits. The value comes %-encoded, a
    # "/" as "%2F" (Tailscale SSH drops a variable whose value holds a "/"),
    # and is decoded first (__ssh_arrangement_decode).
    #   claude:api%2Fdocs -> tmux -L claude attach -t =api/docs
    #   default:main       -> tmux attach -t =main
    #   main, other:x, a/b -> error, shell stays
    # exec, as the remote command did: detaching ends the ssh, and a failed
    # attach (session gone) prints tmux's error and ends it too. Each request
    # and its outcome goes to the tmux_attach_requested event log
    # (~/.dotfiles/.logs/<UTC day>_tmux_attach_requested/events.log).
    set -q LC_TMUX_ATTACH; or return 0

    # Erased first, so nothing started from here inherits the request: a
    # shell left after an error, or one exec'd from this one.
    set -l want $LC_TMUX_ATTACH
    set -e LC_TMUX_ATTACH

    set -l decoded (__ssh_arrangement_decode tmux_attach_requested LC_TMUX_ATTACH $want)
    or return 1
    set -l why
    set -l parts (string split -m 1 : -- "$decoded")
    if set -q TMUX
        set why "reached a shell inside tmux ($TMUX); not nesting a client"
    else if test (count $parts) -ne 2; or test -z "$parts[2]"
        set why "want <socket>:<session>, e.g. claude:ai-agent or default:main"
    else if not contains -- $parts[1] claude default
        set why "socket '$parts[1]' is neither claude nor default"
    end
    if test -n "$why"
        __ssh_arrangement_note tmux_attach_requested "LC_TMUX_ATTACH='$want' refused: $why"
        echo "tmux_attach_requested: LC_TMUX_ATTACH is '$want'; $why" >&2
        return 1
    end

    # Tell iTerm2 which host this is now, before tmux turns on mouse, focus
    # and paste-bracketing modes. iTerm2 resets those on a host change, with
    # a banner each ("Looks like mouse reporting was left on when an ssh
    # session ended unexpectedly..."), so the change has to land while they
    # are off, as a remote prompt's report does before a typed `tmux a`.
    # The hook's report at attach then names the same host: no change.
    #   report here:  local -> remote (modes off) ... attach: remote -> remote
    #   no report:    attach: local -> remote, tmux's modes on -> banners
    if not iterm2_report_host
        __ssh_arrangement_note tmux_attach_requested "LC_TMUX_ATTACH='$want' refused: iterm2_report_host failed"
        return 1
    end

    set -l session $parts[2]
    set -l tmux tmux
    test $parts[1] = default; or set -a tmux -L $parts[1]
    # A request that cannot be logged is not run: the log is what tells a
    # restore that landed in a plain shell from one never received.
    __ssh_arrangement_note tmux_attach_requested "LC_TMUX_ATTACH='$want' on $(tty): exec $tmux attach -t =$session"
    or return 1
    exec $tmux attach -t =$session
end

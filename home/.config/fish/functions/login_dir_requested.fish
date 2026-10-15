function login_dir_requested --description 'cd into the directory LC_LOGIN_DIR names, for a restored iTerm2 ssh tab'
    # A saved iTerm2 ssh arrangement reopens a plain ssh tab in the directory
    # it was in, as a login carrying the directory in the environment, the way
    # tmux_attach_requested gets its session (scripts/lib/iterm2_ssh_arrangement.py,
    # dir_line), and for the same reason: a remote command
    # (`ssh -t vm 'cd d; exec fish -l'`) leaves a Tailscale SSH pty root's.
    #
    #   Mac tab: LC_LOGIN_DIR=%2Fhome%2Fme%2Fd ssh -o SendEnv=LC_LOGIN_DIR vm
    #     -> sshd / tailscaled -> login(1) -> fish --login -> config.fish
    #     -> here: cd /home/me/d
    #
    # The value is %-encoded, "/" too (Tailscale SSH drops a variable whose
    # value holds a "/"), and decoded by __ssh_arrangement_decode:
    #   %2Fhome%2Fme%2Fit%27s%20here -> cd "/home/me/it's here"
    #   home%2Fme                    -> refused: not absolute; shell stays in ~
    #   %2Fgone                      -> cd's own error; shell stays in ~
    # A refusal fails the restore on the Mac, which waits for the tab to
    # report the directory. As in tmux_attach_requested, a request that
    # cannot be logged is not run, and its outcome is logged too, in the
    # login_dir_requested event log
    # (~/.dotfiles/.logs/<UTC day>_login_dir_requested/events.log).
    set -q LC_LOGIN_DIR; or return 0

    # Erased first, so nothing started from here inherits the request.
    set -l want $LC_LOGIN_DIR
    set -e LC_LOGIN_DIR

    set -l dir (__ssh_arrangement_decode login_dir_requested LC_LOGIN_DIR $want)
    or return 1
    # The log says the directory escaped, so it stays one line.
    set -l shown (string escape -- "$dir")
    if not string match -q '/*' -- "$dir"
        __ssh_arrangement_note login_dir_requested "LC_LOGIN_DIR='$want' refused: $shown is not an absolute path"
        echo "login_dir_requested: LC_LOGIN_DIR is '$want'; $shown is not an absolute path" >&2
        return 1
    end

    __ssh_arrangement_note login_dir_requested "LC_LOGIN_DIR='$want' on $(tty): cd $shown"
    or return 1
    # cd prints its own reason (no such directory, permission denied).
    if not cd -- "$dir"
        __ssh_arrangement_note login_dir_requested "LC_LOGIN_DIR='$want': cd $shown failed; staying in $(string escape -- $PWD)"
        return 1
    end
end

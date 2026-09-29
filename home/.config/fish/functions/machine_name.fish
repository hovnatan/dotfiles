function machine_name --description 'Short name of this machine, as the prompt and titles show it'
    # The name up to its first dot ("mbp.local" -> "mbp"). A machine with a
    # long one sets a short name once: `set -U fish_prompt_host mbp`. It lives
    # in fish_variables (gitignored), keeping host names out of this public
    # repo.
    #
    # Not the builtin prompt_hostname: its `string replace` exits 1 when there
    # is no dot to strip ("hov-8cpu"), and ssh-title-flag.sh runs this under
    # `set -e`, so every tmux attach on such a host failed the hook. This
    # match exits 0 for any non-empty name and 1 only when there is none.
    if set -q fish_prompt_host
        echo $fish_prompt_host
    else
        string match -r -- '^[^.]+' $hostname
    end
end

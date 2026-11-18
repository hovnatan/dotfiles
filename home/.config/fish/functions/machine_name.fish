function machine_name --description 'Short name of this machine, as the prompt and titles show it'
    # The rule of scripts/machine_name.sh, which says what the file is for:
    # the one line of ~/.config/dotfiles/machine-name ("mbp"), else the host
    # name up to its first dot ("vm.internal" -> "vm"). Read here with
    # builtins, not by running that script: the prompt asks at every line.
    # Until 2026-11-18 the name was a universal variable, fish_prompt_host,
    # which no other program could read.
    #
    # Not the builtin prompt_hostname: its `string replace` exits 1 when there
    # is no dot to strip ("vm"), which reads as a failure to any caller that
    # checks the status. This match exits 0 for any non-empty name and 1
    # only when there is none.
    set -l file ~/.config/dotfiles/machine-name
    if test -e $file
        read -l name <$file
        echo $name
    else
        string match -r -- '^[^.]+' $hostname
    end
end

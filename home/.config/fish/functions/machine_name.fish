function machine_name --description 'Short name of this machine, as the prompt and titles show it'
    # prompt_hostname is the name up to its first dot. A machine with a long
    # one sets a short name once: `set -U fish_prompt_host mbp`. It lives in
    # fish_variables (gitignored), keeping host names out of this public repo.
    if set -q fish_prompt_host
        echo $fish_prompt_host
    else
        prompt_hostname
    end
end

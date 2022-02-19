function forward-word-or-exit
    set -l cmd (commandline)
    if test -n "$cmd"
        commandline -f forward-word
    else
        exit
    end
end

set -g fish_vi_force_cursor 1

function hybrid_bindings --description "Vi-style bindings that inherit emacs-style bindings in all modes"
    for mode in default insert visual
        fish_default_key_bindings -M $mode
    end
    fish_vi_key_bindings --no-erase
    bind \cp up-or-search
    bind \cn down-or-search
    bind \cd forward-word-or-exit
    bind -M insert \cd forward-word-or-exit
#    bind -M insert -m default jk backward-char force-repaint
#    bind -m insert \e force-repaint
end

set -g fish_key_bindings hybrid_bindings

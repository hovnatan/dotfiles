function hybrid_bindings --description "Vi-style bindings that inherit emacs-style bindings in all modes"
    for mode in default insert visual
        fish_default_key_bindings -M $mode
    end
    fish_vi_key_bindings --no-erase
    bind \cp up-or-search
    bind \cn down-or-search
    bind \cd forward-word
    bind -M insert \cd forward-word
    fzf_key_bindings
end

set -g fish_key_bindings hybrid_bindings

set -U fish_cursor_default block
set -U fish_cursor_insert block blink
set -U fish_cursor_visual block

set -u fish_color_cwd cyan
set -u fish_color_command normal
set -u fish_color_error normal
set -u fish_color_param normal

#if test -d ~/miniconda3/bin
#  set -x PATH ~/miniconda3/bin/ $PATH
#  source (conda info --root)/etc/fish/conf.d/conda.fish
#end

if status --is-login
  source ~/.profile
end

set -x FZF_DEFAULT_OPTS "--bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --height=50% --min-height=15 --reverse"
set -x FZF_CTRL_T_COMMAND "fd -L -p -H . \$dir"
set -x FZF_DEFAULT_COMMAND $FZF_CTRL_T_COMMAND
set -x EDITOR nvim

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
#    bind -M insert -m default jk backward-char force-repaint
end

#set -u fish_term24bit 1

set -g fish_key_bindings hybrid_bindings

set -U fish_cursor_default block
set -U fish_cursor_insert block blink
set -U fish_cursor_visual block

set -u fish_color_cwd brcyan
if [ $TMUX ]
  set -u fish_color_prompt_bg yellow
else
  set -u fish_color_prompt_bg red
end
set -u fish_color_command normal
set -u fish_color_error normal
set -u fish_color_param normal

function bell_on_prompt --on-event fish_prompt
    echo -e -n "\a"
end

set -U fish_user_paths ~/.dotfiles/bin

if test -d ~/anaconda3/bin
  set -U fish_user_paths ~/anaconda3/bin $fish_user_paths
  source (conda info --root)/etc/fish/conf.d/conda.fish
end

abbr v   "$EDITOR ."
abbr z   "zathura"
abbr zd  "zathura -c ~/.config/zathura_lt"
abbr gc  "git-cola"
abbr ta  "tmux_attach_deattached.sh"
abbr rgh "rg --hidden"
abbr mpvhq "mpv --profile=hq"
abbr icat "kitty +kitten icat"

[ -f /usr/share/autojump/autojump.fish ]; and source /usr/share/autojump/autojump.fish

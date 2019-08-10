if status --is-login
  source ~/.profile
end

set -x FZF_DEFAULT_OPTS "--bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --height=50% --min-height=15 --reverse"
set -x FZF_CTRL_T_COMMAND "fd -L -p -H . \$dir"
set -x FZF_DEFAULT_COMMAND $FZF_CTRL_T_COMMAND
set -x EDITOR nvim

function forward-word-or-exit
    set -l cmd (commandline)
    if test -n "$cmd"
        commandline -f forward-word
    else
        exit
    end
end

function hybrid_bindings --description "Vi-style bindings that inherit emacs-style bindings in all modes"
    for mode in default insert visual
        fish_default_key_bindings -M $mode
    end
    fish_vi_key_bindings --no-erase
    bind \cp up-or-search
    bind \cn down-or-search
    bind \cd forward-word-or-exit
    bind -M insert \cd forward-word-or-exit
    fzf_key_bindings
#    bind -M insert -m default jk backward-char force-repaint
#    bind -m insert \e force-repaint
end

set -u fish_term24bit 1

set -g fish_key_bindings hybrid_bindings

set -U fish_cursor_default block
set -U fish_cursor_insert line blink
set -U fish_cursor_visual block

set -u fish_color_cwd brcyan
if [ $TMUX ]
  set light_dark (cat ~/.my_colors)
  if test "$light_dark" = "light"
    set -u fish_color_prompt_bg bdae93
  else
    set -u fish_color_prompt_bg 665c54
  end
else
  set -u fish_color_prompt_bg red
end

set -u fish_color_command normal
set -u fish_color_error normal
set -u fish_color_param normal

function bell_on_prompt --on-event fish_prompt
    echo -e -n "\a"
end

function reload-color-config --on-variable _reload_color_config
  if test "$_reload_color_config" = "light"
    set -u fish_color_prompt_bg bdae93
    set -u fish_color_autosuggestion bdae93
  else
    set -u fish_color_prompt_bg 665c54
    set -u fish_color_autosuggestion 665c54
  end
end

set -U fish_user_paths ~/.dotfiles/bin

[ -f /usr/share/autojump/autojump.fish ]; and source /usr/share/autojump/autojump.fish

abbr c   "cd"
abbr cp  "rsync -a --info=progress2"
abbr n   "nvim"
abbr np   "nvim --noplugin"
abbr nf "nvim (fzf)"
abbr r   "ranger --choosedir="$HOME/.rangerdir"; cd (cat $HOME/.rangerdir)"
abbr z   "zathura"
abbr g   "grep"
abbr gs  "git status"
abbr gp  "git push"
abbr gP  "git pull"
abbr gpp  "git pull"
abbr ga  "git add -u"
abbr gc  "git commit -m"
abbr gd  "git diff"
abbr gah 'git stash; and git pull --rebase; and git stash pop'
abbr gm  "nvim -c MagitOnly"
abbr ta  "tmux_attach_deattached.sh"
abbr tl  "tmux list-sessions"
abbr prg "pdfgrep -ri "
abbr rgh "rg --hidden"
abbr rgah "rga --hidden"
abbr mpvhq "mpv --profile=hq"
abbr mpvnr "mpv --no-resume-playback"
abbr mpvhqnr "mpv --no-resume-playback --profile=hq"
abbr ync "yay --noconfirm"
abbr bc "bc -l"
abbr rf "rm -rfv"
abbr c "cat"
abbr htop "htop -u hovnatan"
abbr p "python"

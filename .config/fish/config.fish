if status --is-login
  umask 0077
  source ~/.profile
  setup_ssh_agent
end

set -x FZF_DEFAULT_OPTS "--bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --height=50% --min-height=15 --reverse"
set -x FZF_CTRL_T_COMMAND "fd -I -p -H -E .git . \$dir"
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

abbr c   "cd"
abbr rsync  "rsync -a --info=progress2"
abbr n   "nvim"
abbr np  "nvim --noplugin"
abbr nvr "nvr -p"

function ranger_fm
  if not set -q RANGER_LEVEL
    ranger --choosedir="$HOME/.rangerdir"; cd (cat $HOME/.rangerdir)
  else
    exit
  end
end
abbr r   ranger_fm
abbr z   "zathura"
abbr g   "grep"
abbr gs  "git status"
abbr gp  "git push"
abbr gP  "git pull"
abbr gpp "git pull"
abbr gl  "nvim +Glog"
abbr gcl "nvim +0Glog"
abbr ga  "git add -u"
abbr gc  "git commit -m"
abbr gca "git commit --amend --no-edit"
abbr gaca "git add -u; git commit --amend --no-edit"
abbr gd  "git diff"
abbr gah 'git stash; and git pull --rebase; and git stash pop'
abbr gm 'nvim (git rev-parse --show-toplevel)/.git/index'
abbr gnof "git merge --no-commit --no-ff"
abbr ta  "tmux_attach_deattached.sh"
abbr tl  "tmux list-sessions"
abbr tc "tmux capture-pane -pJ -S - | nvim -R '+set ft=log|set nowrap|set foldlevel=99|DisableWhitespace' '+norm G' --"
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
abbr htop "htop -u $USER"
abbr p "python"
abbr hm "history merge"
abbr rfc "source ~/.config/fish/config.fish"
abbr pdfgrep "pdfgrep --cache -ri --page-range 1"
abbr ... "../.."
abbr .... "../../.."

# set -gx HOMEBREW_PREFIX "/home/linuxbrew/.linuxbrew";
# set -gx HOMEBREW_CELLAR "/home/linuxbrew/.linuxbrew/Cellar";
# set -gx HOMEBREW_REPOSITORY "/home/linuxbrew/.linuxbrew/Homebrew";
# set -g fish_user_paths "/home/linuxbrew/.linuxbrew/bin" "/home/linuxbrew/.linuxbrew/sbin" $fish_user_paths;
# set -q MANPATH; or set MANPATH ''; set -gx MANPATH "/home/linuxbrew/.linuxbrew/share/man" $MANPATH;
# set -q INFOPATH; or set INFOPATH ''; set -gx INFOPATH "/home/linuxbrew/.linuxbrew/share/info" $INFOPATH;

set -x NVIM_LISTEN_ADDRESS /tmp/nvimsocket
set -x REVIEW_BASE master
set -U Z_CMD "j"

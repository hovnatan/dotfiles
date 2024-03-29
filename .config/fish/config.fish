if status --is-interactive

set -U Z_CMD "j"

set -U FZF_LEGACY_KEYBINDINGS 0
set -U FZF_DEFAULT_OPTS "-i --bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --height=50% --min-height=15 --reverse"
# set -U FZF_COMPLETE 0
set -U FZF_FIND_FILE_COMMAND "fd -IHp --ignore-file ~/.config/fd/ignore . \$dir"
set -U FZF_DEFAULT_COMMAND $FZF_FIND_FILE_COMMAND
set -x EDITOR nvim

set -u fish_term24bit 1

set -U fish_cursor_default block
set -U fish_cursor_insert line
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

abbr c   "fzf_recent_dir"
abbr jj  "fzf_recent_dir"
abbr cdz "fzf_recent_dir"
abbr rsync  "rsync -a --info=progress2"
abbr n   "nvim"
abbr nn  "nvim -u NONE"
abbr np  "nvim --noplugin"

function ranger_fm
  if not set -q RANGER_LEVEL
    ranger --choosedir="$HOME/.rangerdir"; cd (cat $HOME/.rangerdir)
  else
    exit
  end
end
abbr r  ranger_fm
abbr ll  "exa -alh --git"
abbr llb  "exa -al --git"
abbr da  "docker exec -it (docker ps | head -n 2 | tail -n 1 | awk '{print \$1}') /bin/bash"
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
abbr gr "git restore"
abbr ta  "tmux_attach.sh"
abbr tl  "tmux list-sessions"
abbr tc "tmux capture-pane -pJ -S - | nvim -R '+set ft=log|set nowrap|set foldlevel=99|DisableWhitespace' '+norm G' --"
abbr jc "journalctl -b --no-pager | nvim -R '+set ft=log|set nowrap|set foldlevel=99|DisableWhitespace' '+norm G' --"
abbr prg "pdfgrep --cache -ri --page-range 1"
abbr rgh "rg --hidden --no-ignore-vcs"
abbr mhq "mpv --profile=hq"
abbr mhq2 "mpv --profile=hq2"
abbr mhq3 "mpv --profile=hq3"
abbr mnr "mpv --no-resume-playback"
abbr mhqnr "mpv --no-resume-playback --profile=hq"
abbr ync "yay --noconfirm"
abbr bc "bc -l"
abbr rf "rm -rfvI"
abbr b "bat"
abbr cat "bat"
abbr h "htop"
abbr hh "htop -u $USER"
abbr p "python"
abbr hm "history merge"
abbr rfc "source ~/.config/fish/config.fish"
abbr ... "../.."
abbr .... "../../.."
abbr pd "python3 -m ipdb -c continue"
abbr pip_update_outdated "pip list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1  | xargs -n1 pip install -U"

set -u VIRTUAL_ENV_DISABLE_PROMPT 1

end

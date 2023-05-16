if status --is-interactive

zoxide init fish | source

set -U FZF_LEGACY_KEYBINDINGS 0
set -U FZF_DEFAULT_OPTS "-i --bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --height=50% --min-height=15 --reverse"
# set -U FZF_COMPLETE 0
set -U FZF_FIND_FILE_COMMAND "fdfind -IHp --ignore-file ~/.config/fd/ignore . \$dir"
set -U FZF_DEFAULT_COMMAND $FZF_FIND_FILE_COMMAND
set -U FZF_TMUX 1
set -U FZF_ENABLE_OPEN_PREVIEW 1
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


bind -M insert \cg forget

function __zoxide_zi_c
    set -l result (command zoxide query --interactive -- $argv)
    and __zoxide_cd $result
    commandline -f repaint
end
bind -M insert \ec  __zoxide_zi_c

abbr ll  "ls -aslh"
abbr rsync  "rsync -a --info=progress2"
abbr n   "nvim"
abbr nn  "nvim -u NONE"
abbr np  "nvim --noplugin"
abbr g   "grep"

function ranger_fm
  if not set -q RANGER_LEVEL
    ranger --choosedir="$HOME/.rangerdir"; cd (cat $HOME/.rangerdir)
  else
    exit
  end
end

abbr da  "docker exec -it (docker ps | head -n 2 | tail -n 1 | awk '{print \$1}') /bin/bash"
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
abbr b "batcat"
abbr h "htop"
abbr hh "htop -u $USER"
abbr p "python"
abbr pd "python3 -m ipdb -c continue"
abbr pu "pipdeptree --warn silence | grep -E '(^\S+)' | awk -F== '{print\$1}' | xargs pip3 install -U"
abbr hm "history merge"
abbr rfc "source ~/.config/fish/config.fish"
abbr ... "../.."
abbr .... "../../.."
abbr sv "source .venv/bin/activate.fish"
abbr xt "TERM=xterm-256color"

set -u VIRTUAL_ENV_DISABLE_PROMPT 1
set -u fish_command_timer_enabled 1
set -u fish_command_timer_export_only_string 1
set -u fish_command_timer_time_format '%b %d %T'

end

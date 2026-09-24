if status --is-interactive

# atuin init fish --disable-up-arrow | source

set -U FZF_LEGACY_KEYBINDINGS 0
set -U FZF_DEFAULT_OPTS "-i --bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --height=50% --min-height=15 --reverse"
# set -U FZF_COMPLETE 0
set -U FZF_FIND_FILE_COMMAND "fd -IHp --ignore-file ~/.config/fd/ignore . \$dir"
set -U FZF_DEFAULT_COMMAND $FZF_FIND_FILE_COMMAND
set -U FZF_TMUX 1
set -U FZF_ENABLE_OPEN_PREVIEW 1
set -x EDITOR nvim

set -u fish_term24bit 1

set -U fish_cursor_default block
set -U fish_cursor_insert line
set -U fish_cursor_visual block

set -u fish_color_cwd brcyan
# ~/.my_colors (light|dark) is optional machine state that scripts/cw.sh
# writes; without it the dark prompt colour applies.
if [ $TMUX ]
  set light_dark
  test -r ~/.my_colors; and set light_dark (cat ~/.my_colors)
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
# The default theme's brblack is palette 8, which Ghostty's GitLab Light sets
# to the foreground (#303030), so suggestions looked like typed text. The normal
# colour dimmed (SGR 2, as the Claude Code statusline does) reads as a hint on
# both the light and the dark background.
set -u fish_color_autosuggestion normal --dim

# When a command taking > 1s finishes: ring the terminal bell (tmux window
# flag, Ghostty dock bounce + title mark) and post a macOS notification via
# OSC 777 (Ghostty desktop-notifications; suppressed by Ghostty while the
# surface is focused). Inside tmux the OSC must be wrapped in the passthrough
# envelope (needs allow-passthrough, .tmux.conf); the bell needs no wrapping
# (monitor-bell/bell-action forward it). Same behaviour as the zsh hook in
# .zshrc.shared; fish hands postexec the command line and $CMD_DURATION (ms).
#   `sleep 2` -> bell + "Command finished (2.0s);sleep 2"; `true` -> nothing
function __bell_on_long_command --on-event fish_postexec
    test "$CMD_DURATION" -gt 1000; or return
    set -l elapsed (printf '%.1f' (math $CMD_DURATION / 1000))
    set -l cmd (string replace -a \n ' ' -- $argv[1] | string sub -l 80)
    printf '\a'
    set -l osc \e"]777;notify;Command finished ("$elapsed"s);$cmd"\a
    if set -q TMUX
        printf '%s' \ePtmux\;(string replace -a \e \e\e -- $osc)\e\\
    else
        printf '%s' $osc
    end
end

function reload-color-config --on-variable _reload_color_config
  if test "$_reload_color_config" = "light"
    set -u fish_color_prompt_bg bdae93
  else
    set -u fish_color_prompt_bg 665c54
  end
end


bind -M insert \cg forget

abbr rsync  "rsync -a --info=progress2"
abbr ll  "ls -aslh"
abbr n   "nvim"
abbr g   "grep"
abbr da  "docker exec -it (docker ps | head -n 2 | tail -n 1 | awk '{print \$1}') /bin/bash"
abbr ta  "~/.dotfiles/scripts/tmux_attach.sh"
abbr dotup "~/.dotfiles/scripts/update.sh"
abbr tl  "tmux list-sessions"
abbr tc  "tmux capture-pane -pJ -S - | nvim -R '+set ft=log|set nowrap|set foldlevel=99' '+norm G' --"
abbr jc  "journalctl -b --no-pager | nvim -R '+set ft=log|set nowrap|set foldlevel=99' '+norm G' --"
abbr prg "pdfgrep --cache -ri --page-range 1"
abbr rgh "rg --hidden --no-ignore-vcs"
abbr bc  "bc -l"
abbr rf  "rm -rfvI"
abbr h   "htop"
abbr hh  "htop -u $USER"
abbr p   "python"
abbr pd  "python3 -m ipdb -c continue"
abbr pu  "pipdeptree --warn silence | grep -E '^[a-zA-Z]+' | awk -F== '{print\$1}' | xargs pip3 install -U"
abbr hm  "history merge"
abbr rfc "source ~/.config/fish/config.fish"
abbr ... "../.."
abbr sv  "source .venv/bin/activate.fish"
abbr xt  "TERM=xterm-256color"

set -u VIRTUAL_ENV_DISABLE_PROMPT 1
set -u fish_command_timer_enabled 1
set -u fish_command_timer_export_only_string 1
set -u fish_command_timer_time_format '%b %d %T'

end

if status --is-interactive

# atuin init fish --disable-up-arrow | source

set -U FZF_LEGACY_KEYBINDINGS 0
set -U FZF_DEFAULT_OPTS "-i --bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all --height=50% --min-height=15 --reverse"
# set -U FZF_COMPLETE 0
set -U FZF_FIND_FILE_COMMAND "fd -IHp --ignore-file ~/.config/fd/ignore . \$dir"
set -U FZF_DEFAULT_COMMAND $FZF_FIND_FILE_COMMAND
set -U FZF_TMUX 1
set -U FZF_ENABLE_OPEN_PREVIEW 1
# nvim where installed, else vim; same rule as home/.profile.shared
if type -q nvim
    set -x EDITOR nvim
else
    set -x EDITOR vim
end

set -u fish_term24bit 1

set -U fish_cursor_default block
set -U fish_cursor_insert line
set -U fish_cursor_visual block

set -u fish_color_cwd brcyan
if [ $TMUX ]
  set -u fish_color_prompt_bg 665c54
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
# The part of a history-search result (ctrl-p/Up) that matched what was typed.
# The theme's white on brblack showed as a grey block over the prefix; bold in
# the normal colour still marks it and reads on light and dark backgrounds.
# The completion pager's selected row does not fall back to this: the theme
# sets fish_pager_color_selected_background (reverse video) itself.
set -u fish_color_search_match normal --bold

# When a command taking > 1s finishes, ring the terminal bell: tmux window
# flag, Ghostty/iTerm2 dock bounce + tab mark. tmux forwards the bell
# natively (monitor-bell/bell-action, .tmux.conf), so it needs no
# passthrough wrapping. No desktop notification on purpose: it doubled
# iTerm2's dock count and tmux dropped it for hidden panes. Same behaviour
# as the zsh hook in .zshrc.shared; fish hands postexec $CMD_DURATION (ms).
#   `sleep 2` -> bell; `true` -> nothing
function __bell_on_long_command --on-event fish_postexec
    test "$CMD_DURATION" -gt 1000; or return
    printf '\a'
end

# Workaround for a Claude Code bug (seen in 2.1.289): cancelling the
# `claude --resume` picker (Esc) exits with the cursor parked mid-frame,
# without erasing the frame below it. zsh's prompt clears to the end of
# the screen and hides it; fish (and bash) draw the prompt in place and
# leave the rest of the session list under it. Return to column 0 and
# erase to the end of the screen after any `claude` command. After a
# clean exit the cursor already sits on an empty line, so this is a no-op.
# Drop once https://github.com/anthropics/claude-code/issues/99718 is fixed.
#   `claude --resume`, Esc -> prompt right under the search box, no list
function __clear_after_claude --on-event fish_postexec
    string match -rq '^\s*claude(\s|$)' -- $argv[1]; or return
    printf '\r\e[J'
end


bind -M insert \cg forget

abbr rsync  "rsync -a --info=progress2"
abbr ll  "ls -aslh"
abbr n   "nvim"
# vim runs nvim where it is installed; machines without it keep plain vim
if type -q nvim
    function vim --wraps nvim
        nvim $argv
    end
end
abbr g   "grep"
abbr da  "docker exec -it (docker ps | head -n 2 | tail -n 1 | awk '{print \$1}') /bin/bash"
abbr ta  "~/.dotfiles/scripts/tmux_attach.sh"
abbr dotup "~/.dotfiles/scripts/update.sh"
abbr df  "df -h"
abbr du  "du -h"
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

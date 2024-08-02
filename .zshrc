autoload -U colors && colors
PS1="%B%{$fg[green]%}%n@%{$fg[green]%}%m%{$reset_color%}:%B%{$fg[blue]%}%(5~|%-1~/.../%3~|%4~)%{$reset_color%}%% "

setopt histignorealldups
setopt sharehistory
setopt alwaystoend
setopt automenu
setopt noautolist
setopt nobeep
setopt incappendhistory
setopt histsavenodups
setopt nocaseglob

bindkey -v

bindkey "^P" up-line-or-search
bindkey "^N" down-line-or-search
bindkey "^R" history-incremental-pattern-search-backward
bindkey "^A" vi-beginning-of-line
bindkey "^E" vi-end-of-line

export KEYTIMEOUT=1
cursor_mode() {
    # See https://ttssh2.osdn.jp/manual/4/en/usage/tips/vim.html for cursor shapes
    cursor_block='\e[2 q'
    cursor_beam='\e[6 q'
    function zle-keymap-select {
        if [[ ${KEYMAP} == vicmd ]] ||
            [[ $1 = 'block' ]]; then
            echo -ne $cursor_block
        elif [[ ${KEYMAP} == main ]] ||
            [[ ${KEYMAP} == viins ]] ||
            [[ ${KEYMAP} = '' ]] ||
            [[ $1 = 'beam' ]]; then
            echo -ne $cursor_beam
        fi
    }
    zle-line-init() {
        echo -ne $cursor_beam
    }
    zle -N zle-keymap-select
    zle -N zle-line-init
}
cursor_mode

zmodload zsh/complist

bindkey -M menuselect '^M' accept-line
# bindkey -M menuselect '^O' history-incremental-search-forward
bindkey -M menuselect '^O' vi-insert
bindkey -M menuselect '^H' vi-backward-char
bindkey -M menuselect '^K' vi-up-line-or-history
bindkey -M menuselect '^J' vi-down-line-or-history
bindkey -M menuselect '^L' vi-forward-char
bindkey -M menuselect '^?' backward-delete-char
bindkey -M menuselect '^[[Z' reverse-menu-complete
bindkey -M menuselect '^[' undo

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

fpath=(~/.docker/completions \\$fpath)
autoload -Uz compinit && compinit
autoload -Uz bashcompinit && bashcompinit

_comp_options+=(globdots)

zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %d --%f'
zstyle ':completion:*:*:*:*:corrections' format '%F{yellow}!- %d (errors: %e) -!%f'
zstyle ':completion:*:messages' format ' %F{purple} -- %d --%f'
zstyle ':completion:*:warnings' format ' %F{red}-- no matches found --%f'
zstyle ':completion:*' completer _expand_alias _expand _complete _correct _approximate
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt ''
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' select-prompt ''
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*' file-sort modification

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

import_miniconda() {
  # >>> conda initialize >>>
  # !! Contents within this block are managed by 'conda init' !!
  __conda_setup="$("$HOME/miniforge3/bin/conda" 'shell.bash' 'hook' 2> /dev/null)"
  if [ $? -eq 0 ]; then
    eval "$__conda_setup"
  else
    if [ -f "$HOME/miniforge3/etc/profile.d/conda.sh" ]; then
      . "$HOME/miniforge3/etc/profile.d/conda.sh"  # commented out by conda initialize
    else
      export PATH="$HOME/miniforge3/bin:$PATH"  # commented out by conda initialize
    fi
  fi
  unset __conda_setup
  # <<< conda initialize <<<
}

alias update="sudo apt update && sudo apt -y dist-upgrade && sudo apt -y autoremove && sudo fwupdmgr update && sudo snap refresh --list && sudo snap refresh && cat /var/run/reboot-required"
alias ta="tmux a -t"
alias tl="tmux ls"
alias ll='ls -alG'
alias ta='tmux a -t'
alias gd='git diff'
alias gst='git status'
alias gp='git push'
alias gl='git pull'
alias gau='git add -u'
alias gcm='git commit -m'

umask 0077

export EDITOR=vim

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

export COLORTERM=truecolor

export MAKEFLAGS="-j11"
export CFLAGS="-march=native -O3"
export CXXFLAGS="-march=native -O3"

_hydra_bash_completion()
{
    words=($COMP_LINE)
    if [ "${words[0]}" == "python" ]; then
        if (( ${#words[@]} < 2 )); then
            return
        fi
        file_path=$(pwd)/${words[1]}
        if [ ! -f "$file_path" ]; then
            return
        fi
        grep "@hydra.main" $file_path -q
        helper="${words[0]} ${words[1]}"
    else
        helper="${words[0]}"
        true
    fi

    EXECUTABLE=($(command -v $helper))
    if [ "$HYDRA_COMP_DEBUG" == "1" ]; then
        printf "EXECUTABLE_FIRST='${EXECUTABLE[0]}'\n"
    fi
    if ! [ -x "${EXECUTABLE[0]}" ]; then
        false
    fi

    if [ $? == 0 ]; then
        choices=$( COMP_POINT=$COMP_POINT COMP_LINE=$COMP_LINE $helper -sc query=bash)
        word=${words[$COMP_CWORD]}

        if [ "$HYDRA_COMP_DEBUG" == "1" ]; then
            printf "\n"
            printf "COMP_LINE='$COMP_LINE'\n"
            printf "COMP_POINT='$COMP_POINT'\n"
            printf "Word='$word'\n"
            printf "Output suggestions:\n"
            printf "\t%s\n" ${choices[@]}
        fi
        COMPREPLY=($( compgen -o nospace -o default -W "$choices" -- "$word" ));
    fi
}


hydra_completion() {
  export _HYDRA_OLD_COMP=$(complete -p python 2> /dev/null)
  COMP_WORDBREAKS=${COMP_WORDBREAKS//=}
  COMP_WORDBREAKS=$COMP_WORDBREAKS complete -o nospace -o default -F _hydra_bash_completion python
}

if [[ -f "$HOME/.zshrc_local" ]]; then
    source "$HOME/.zshrc_local"
fi

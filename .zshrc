export SHELL="/bin/zsh"

autoload -U colors && colors

setopt PROMPT_SUBST

path_abbrev() {
  local full_path=${PWD/#$HOME/\~}
  local path_parts=("${(s:/:)full_path}")
  local result=""

  if [[ ${#path_parts[@]} -eq 1 ]]; then
    # If there's only one component (root or home), just return it
    echo $full_path
    return
  fi

  if [[ ${path_parts[1]} == "~" ]]; then
    result="~/"
  else
    result="/"
  fi

  for ((i=2; i<${#path_parts[@]}; i++)); do
    if [[ -n ${path_parts[i]} ]]; then
      result+="${path_parts[i]:0:1}/"
    else
      result+="/"
    fi
  done

  # Add the last component without a trailing slash
  result+="${path_parts[-1]}"
  echo $result
}

# Function to get git information
git_prompt_info() {
  local ref
  if [[ "$(command git config --get oh-my-zsh.hide-status 2>/dev/null)" != "1" ]]; then
    ref=$(command git symbolic-ref HEAD 2> /dev/null) || \
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return 0
    echo "(${ref#refs/heads/})"
  fi
}

# Function to get git status
git_prompt_status() {
  local STATUS=""
  local -a FLAGS
  FLAGS=('--porcelain')
  if [[ "$(command git config --get oh-my-zsh.hide-dirty)" != "1" ]]; then
    if [[ $POST_1_7_2_GIT -gt 0 ]]; then
      FLAGS+='--ignore-submodules=dirty'
    fi
    if [[ "$DISABLE_UNTRACKED_FILES_DIRTY" == "true" ]]; then
      FLAGS+='--untracked-files=no'
    fi
    STATUS=$(command git status ${FLAGS} 2> /dev/null | tail -n1)
  fi
  if [[ -n $STATUS ]]; then
    echo "%{$fg[red]%}"
  else
    echo "%{$fg[green]%}"
  fi
}

# Set the prompt
PS1='%B%{$fg[green]%}%n@%{$fg[green]%}%m%{$reset_color%}:%B%{$fg[blue]%}$(path_abbrev)%{$reset_color%}$(git_prompt_status)$(git_prompt_info)%{$reset_color%}%{$fg[red]%}%(?..%B[%?])%{$reset_color%}%% '

# Function to set the terminal title
set_terminal_title() {
    local title="$1"
    if (( ${#title} > 20 )); then
        title="...${title: -17}"
    fi
    title=$(printf '%20.20s' "${title}")
    print -P "\e]0;$title\a"
}

# Function to be executed before each prompt
precmd_terminal_title() {
    set_terminal_title "$(path_abbrev)"
}

# Function to be executed just before a command is executed
preexec_terminal_title() {
    local cmd="$1"
    # Remove leading environment variables or sudo
    # cmd="${cmd#*=}"
    # cmd="${cmd#sudo }"
    # Truncate the command if it's too long
    set_terminal_title "$cmd"
}

# Add our functions to the respective hook arrays
precmd_functions+=(precmd_terminal_title)
preexec_functions+=(preexec_terminal_title)

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

bindkey -M viins '^[[A' up-line-or-history
bindkey -M viins '^[[B' down-line-or-history
bindkey -M viins '^[[D' backward-char
bindkey -M viins '^[[C' forward-char
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^[[3~' delete-char

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

# umask 0077

export EDITOR=vim

# export LC_ALL=en_US.UTF-8
# export LANG=en_US.UTF-8
# export LANGUAGE=en_US.UTF-8
# export LC_ALL=C.utf-8

export COLORTERM=truecolor

export MAKEFLAGS="-j11"
export CFLAGS="-march=native -O3"
export CXXFLAGS="-march=native -O3"

########################################################################################

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

########################################################################################
# from https://github.com/kadaan/per-directory-history/blob/master/per-directory-history.zsh

# An implementation of per-directory history.
# See README.md for more information.

[[ -z $_per_directory_history_is_global ]] && _per_directory_history_is_global=true
[[ -z $PER_DIRECTORY_HISTORY_BASE ]] && PER_DIRECTORY_HISTORY_BASE="$HOME/.zsh_history_dirs"
[[ -z $PER_DIRECTORY_HISTORY_FILE ]] && PER_DIRECTORY_HISTORY_FILE="zsh-per-directory-history"
[[ -z $PER_DIRECTORY_HISTORY_TOGGLE ]] && PER_DIRECTORY_HISTORY_TOGGLE='^g'

#-------------------------------------------------------------------------------
# toggle global/directory history used for searching - alt-l by default
#-------------------------------------------------------------------------------

function per-directory-history-toggle-history() {
	if $_per_directory_history_is_global
	then
		_per-directory-history-set-directory-history
    zle -I
    echo "using local history"
	else
		_per-directory-history-set-global-history
    zle -I
    echo "using global history"
	fi
}

autoload per-directory-history-toggle-history
zle -N per-directory-history-toggle-history
bindkey $PER_DIRECTORY_HISTORY_TOGGLE per-directory-history-toggle-history
bindkey -M vicmd $PER_DIRECTORY_HISTORY_TOGGLE per-directory-history-toggle-history

#-------------------------------------------------------------------------------
# implementation details
#-------------------------------------------------------------------------------

_per_directory_history_path="$PER_DIRECTORY_HISTORY_BASE${PWD:A}/$PER_DIRECTORY_HISTORY_FILE"

function _per-directory-history-change-directory() {
	_per_directory_history_path="$PER_DIRECTORY_HISTORY_BASE${PWD:A}/$PER_DIRECTORY_HISTORY_FILE"
	if ! $_per_directory_history_is_global
	then
		fc -P
		mkdir -p ${_per_directory_history_path:h}
		fc -p $_per_directory_history_path
	fi
}

function _per-directory-history-addhistory() {
	# respect hist_ignore_space
	if [[ -o hist_ignore_space ]] && [[ "$1" == \ * ]]
	then
		return
	fi

	# Can't write to history (print -S) from addhistory,
	# save command to be added later from preexec hook
	_per_directory_history_pending_cmd="${1%%$'\n'}"
}

_per_directory_history_last_cmd=''

function _per-directory-history-preexec() {
	if [[ -v _per_directory_history_pending_cmd ]]
	then
		if [[ "$_per_directory_history_pending_cmd" != "$_per_directory_history_last_cmd" ]]
		then
			local fn
			if $_per_directory_history_is_global
			then
				mkdir -p ${_per_directory_history_path:h}
				fn=$_per_directory_history_path
			else
				fn=$_per_directory_history_main_histfile
			fi

			fc -p
			print -Sr -- $_per_directory_history_pending_cmd
			SAVEHIST=1
			fc -A $fn
			fc -P

			_per_directory_history_last_cmd=$_per_directory_history_pending_cmd
		fi

		unset _per_directory_history_pending_cmd
	fi
}


function _per-directory-history-set-directory-history() {
	fc -P

	mkdir -p ${_per_directory_history_path:h}
	fc -p $_per_directory_history_path
	_per_directory_history_is_global=false
}
function _per-directory-history-set-global-history() {
	fc -P

	fc -p $_per_directory_history_main_histfile
	_per_directory_history_is_global=true
}


#add functions to the exec list for chpwd and zshaddhistory
autoload -U add-zsh-hook
add-zsh-hook chpwd _per-directory-history-change-directory
add-zsh-hook zshaddhistory _per-directory-history-addhistory
add-zsh-hook preexec _per-directory-history-preexec

_per_directory_history_main_histfile=$HISTFILE
unset HISTFILE

_per-directory-history-set-directory-history
########################################################################################


if [[ -f "$HOME/.zshrc_local" ]]; then
    source "$HOME/.zshrc_local"
fi
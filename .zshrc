fortune
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

autoload -Uz compinit promptinit
compinit
promptinit

# This will set the default prompt to the walters theme
PROMPT='%B%(?..[%?] )%b%n@%m%u %% '
RPROMPT="%F{${1:-blue}}%~%f"

autoload -Uz compinit
compinit

function update_title() {
  local a
  # escape '%' in $1, make nonprintables visible
  a=${(V)1//\%/\%\%}
  a=$(print -n "%20>...>$a")
  # remove newlines
  a=${a//$'\n'/}
  if [[ -n "$TMUX" ]]; then
    print -n "\ek${(%)a}\e\\"
  elif [[ "$TERM" =~ "screen*" ]]; then
    print -n "\ek${(%)a}\e\\"
  elif [[ "$TERM" =~ "xterm*" ]]; then
    print -n "\e]0;${(%)a}\a"
  elif [[ "$TERM" =~ "^rxvt-unicode.*" ]]; then
    printf '\33]2;%s:%s\007' ${(%)a}
  fi
}

function update_title1() {
  if [[ -n "$TMUX" ]]; then
    print -n "\ek${(%)1}\e\\"
  elif [[ "$TERM" =~ "screen*" ]]; then
    print -n "\ek${(%)1}\e\\"
  elif [[ "$TERM" =~ "xterm*" ]]; then
    print -n "\e]0;${(%)1}\a"
  elif [[ "$TERM" =~ "^rxvt-unicode.*" ]]; then
    printf '\33]2;%s:%s\007' ${(%)1}
  fi
}

# called just before the prompt is printed
function _zsh_title__precmd() {
  update_title1 "%20<...<%~"
}

# called just before a command is executed
function _zsh_title__preexec() {
  local -a cmd; cmd=(${(z)1})             # Re-parse the command line

  # Construct a command that will output the desired job number.
  case $cmd[1] in
    fg)	cmd="${(z)jobtexts[${(Q)cmd[2]:-%+}]}" ;;
    %*)	cmd="${(z)jobtexts[${(Q)cmd[1]:-%+}]}" ;;
  esac
  update_title "$cmd"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zsh_title__precmd
add-zsh-hook preexec _zsh_title__preexec

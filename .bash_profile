source ~/.profile
source ~/.zprofile

# x11-over-vsock &
# export XURL=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
# export DISPLAY="$XURL:0.0"

export NVIM_LISTEN_ADDRESS=/tmp/nvimsocket
export REVIEW_BASE=master

export PATH="`python3 -m site --user-base`/bin:$PATH"
export PATH="/usr/local/bin:$PATH"

export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"

export PATH="/usr/local/Cellar/ncurses/6.2/bin:$PATH"

export PATH="/usr/local/opt/man-db/libexec/bin:$PATH"

source ~/.bashrc
source ~/.bashrc_local

import_miniconda() {
  # >>> conda initialize >>>
  # !! Contents within this block are managed by 'conda init' !!
  __conda_setup="$("$HOME/miniconda3/bin/conda" 'shell.bash' 'hook' 2> /dev/null)"
  if [ $? -eq 0 ]; then
    eval "$__conda_setup"
  else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
      . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
      export PATH="$HOME/miniconda3/bin:$PATH"
    fi
  fi
  unset __conda_setup
  # <<< conda initialize <<<
}

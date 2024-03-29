umask 0077

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# export TERM="alacritty"
export TERMINFO_DIRS="$TERMINFO_DIRS:$HOME/.local/share/terminfo"
export TMUX_ONE_WINDOW=1
# export LIBGL_ALWAYS_INDIRECT=1
export MAKEFLAGS="-j11"

export NVIM_LISTEN_ADDRESS=/tmp/nvimsocket
export REVIEW_BASE=master

export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/Cellar/ncurses/6.3/bin:$PATH"
export PATH="/opt/homebrew/opt/node@16/bin:$PATH"
export LDFLAGS="-L/opt/homebrew/opt/node@16/lib"
export CPPFLAGS="-I/opt/homebrew/opt/node@16/include"
# export PATH="/opt/homebrew/Cellar/llvm/13.0.1_1/bin/:$PATH"
export PATH="/opt/homebrew/opt/man-db/libexec/bin:$PATH"
export PATH="/opt/homebrew/opt/mongodb-community@4.4/bin:$PATH"
export PATH="`python3 -m site --user-base`/bin:$PATH"

export PATH="$HOME/opt/usr/bin:$PATH"
. "$HOME/.cargo/env"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.dotfiles/bin:$PATH"
export PATH="$HOME/.dotfiles/sandboxtron/bin:$PATH"


# export PYTHONBREAKPOINT=pudb.remote.set_trace
export PYTHONBREAKPOINT=ipdb.set_trace

export RIPGREP_CONFIG_PATH="$HOME/.dotfiles/.ripgreprc"

SSH_ENV="$HOME/.ssh/agent-environment"

function start_agent {
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    /usr/bin/ssh-add > /dev/null 2>&1

    ssh_keys=$(find ~/.ssh -type f -name '*.pem' -o -name "*.rsa")
    ssh_agent_keys=$(ssh-add -l | awk '{key=NF-1; print $key}')

    for k in "${ssh_keys}"; do
        for l in "${ssh_agent_keys}"; do
            if [[ ! "${k}" = "${l}" ]]; then
                ssh-add "${k}" > /dev/null 2>&1
            fi
        done
    done
}

if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || {
        start_agent;
    }
else
    start_agent;
fi

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

if [ -z "${SSH_CONNECTION}" ]; then
  export MY_IP="127.0.0.1"
else
  export MY_IP=$("$HOME/.dotfiles/bin/get_my_ip.sh")
fi

export CONDA_EXPERIMENTAL_SOLVER=libmamba

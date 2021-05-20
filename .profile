umask 0077

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# export TERM="alacritty"
export TMUX_ONE_WINDOW=1
# export LIBGL_ALWAYS_INDIRECT=1
export MAKEFLAGS="-j11"

export CUDA_HOME=/usr/local/cuda
export PATH="$CUDA_HOME/bin:$PATH"
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$HOME/opt/usr/bin:$HOME/.cargo/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

export QT_SCALE_FACTOR="1.5"
export PYTHONBREAKPOINT=pudb.remote.set_trace

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

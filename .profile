umask 0077

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# export TERMINAL_APP="termite"
# export TMUX_ONE_WINDOW=1
# export LIBGL_ALWAYS_INDIRECT=1
export MAKEFLAGS="-j15"

export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$HOME/opt/usr/bin:$PATH"
export CUDA_HOME=/usr/local/cuda
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
export PATH="/snap/bin:$PATH"

export XURL=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
export DISPLAY="$XURL:0.0"

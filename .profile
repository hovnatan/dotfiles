umask 0077

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# export TERMINAL_APP="termite"
export TMUX_ONE_WINDOW=1
# export LIBGL_ALWAYS_INDIRECT=1
export MAKEFLAGS="-j11"

export CUDA_HOME=/usr/local/cuda
export PATH="$CUDA_HOME/bin:$PATH"
export PATH="$HOME/.dotfiles/bin:$HOME/.local/bin:$HOME/opt/usr/bin:$HOME/.cargo/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

export QT_SCALE_FACTOR="1.5"
export PYTHONBREAKPOINT=pudb.remote.set_trace

export DISPLAY=:0

source ~/.profile

# x11-over-vsock &
export XURL=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
export DISPLAY="$XURL:0.0"

export NVIM_LISTEN_ADDRESS=/tmp/nvimsocket
export REVIEW_BASE=master

source ~/.bashrc
source ~/.bashrc_local

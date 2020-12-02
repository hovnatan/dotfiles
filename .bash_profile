source ~/.profile

# x11-over-vsock &
export XURL=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
export DISPLAY="$XURL:0.0"

source ~/.bashrc
source ~/.bashrc_local

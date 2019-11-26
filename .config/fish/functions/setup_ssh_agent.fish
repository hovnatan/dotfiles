function setup_ssh_agent --description 'Setup SSH agent'
  pgrep -u "$USER" ssh-agent > /dev/null
  if test $status -ne 0
    ssh-agent -c > "$XDG_RUNTIME_DIR/ssh-agent.env"
  end

  if set -q SSH_AUTH_SOCK
    set -l vals (cat "$XDG_RUNTIME_DIR/ssh-agent.env")
    eval "$vals"
  end
end

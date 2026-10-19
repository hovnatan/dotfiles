#!/usr/bin/env bash
# prefix C-r (~/.tmux.conf): restart the claude in the session in view, in
# place -- `claude_tmux_run.sh restart`, behind a confirm prompt that names
# the work the restart would kill (a turn, background shells), with its
# verdict on the message line.
#
#   restart-claude.sh ask <socket path> <session> <client>   the binding
#   restart-claude.sh go  <socket path> <session> <client>   the prompt's y
#
#   C-r --> ask: the claude socket? --- no ---------> "not a claude session"
#                restart --check ------ refused ----> its reason
#                confirm-before "restart claude in <s>?[ it kills <work>] (y/n)"
#    y  --> go:  restart --force (the work was in the prompt, and the pane
#                shows whether a turn really runs: "busy" alone cannot)
#                its last line ----------------------> the message line
#
# The prompt's command carries no data of its own: tmux fills its formats
# in when y runs it, from the same client and session, so nothing here has
# to survive tmux's command parser. A prompt is a format, hence "#" doubled.
# Only the claude socket (or the one a test names): elsewhere -- a default
# tmux server, a Mac, which has no claude socket -- claude_tmux_run.sh has
# no session to act on and its errors would only mislead. The restart logs
# every step under ~/.dotfiles/.logs/<UTC>_claude_tmux_restart/.
#
# A refusal is reported on the message line and exits 0: run-shell answers
# a non-zero exit by opening a "returned 1" view over the pane, which hides
# the message that says why.
set -u

[ $# -eq 4 ] || {
  echo "usage: restart-claude.sh ask|go <socket path> <session> <client>" >&2
  exit 2
}
step=$1 socket=$2 session=$3 client=$4
run="$HOME/.dotfiles/scripts/claude_tmux_run.sh"

# The client is -c to display-message, but -t to confirm-before (its -c is
# the confirm key); confirm-before takes -b, or this process waits for the
# answer, forever when the client leaves without giving one.
say() { tmux -S "$socket" display-message -l -d 8000 -c "$client" "C-r: $1"; }

if [ "${socket##*/}" != "${CLAUDE_TMUX_SOCKET:-claude}" ]; then
  say "not a claude session (tmux socket ${socket##*/}); nothing to restart"
  exit 0
fi
export CLAUDE_TMUX_SOCKET="${socket##*/}"

case "$step" in
  ask)
    if ! work=$("$run" restart --check "$session" 2>&1); then
      say "$(tail -n 1 <<<"$work")"
      exit 0
    fi
    prompt="restart claude in $session?"
    [ -z "$work" ] || prompt+=" it kills $(cut -c1-100 <<<"$work")"
    tmux -S "$socket" confirm-before -b -t "$client" -p "${prompt//#/##} (y/n)" \
      "run-shell -b \"~/.dotfiles/home/.config/tmux/restart-claude.sh go #{q:socket_path} #{q:session_name} #{q:client_name}\""
    ;;
  go)
    # The verdict is the restart's last line, its log stamp dropped.
    out=$("$run" restart --force "$session" 2>&1)
    say "$(tail -n 1 <<<"$out" | sed 's/^[0-9]*-[0-9]*-[0-9]*T[0-9:]*Z //')"
    ;;
  *)
    echo "restart-claude.sh: unknown step '$step' (ask or go)" >&2
    exit 2
    ;;
esac

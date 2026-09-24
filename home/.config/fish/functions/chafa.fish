# chafa (nix/flake.nix) with Kitty graphics through tmux.
#
# Inside a tmux pane TERM and TERM_PROGRAM name tmux, not the terminal behind
# it, so chafa's own detection falls back to symbols, and even with -f kitty
# it does not wrap its output for tmux. Ask tmux which terminal the attached
# client is: Ghostty or kitty -> `-f kitty --passthrough tmux` (tmux has
# allow-passthrough on); anything else, e.g. a VS Code terminal on the same
# session, keeps chafa's own choice. Flags given on the command line come
# later and win, so `chafa -f symbols img` still gets symbols.
#
# Slow to appear over ssh: chafa sends raw pixels, ~25 MB for a full-pane
# screenshot, and the prompt returns long before they reach the terminal
# (compression requested upstream: hpjansson/chafa#356). Probing is not the
# cost - tmux answers chafa's queries itself, 57 ms per run with or without.
function chafa --wraps chafa --description 'chafa, with Kitty graphics through tmux'
    if set -q TMUX; and string match -qr 'ghostty|kitty' -- (tmux display-message -p '#{client_termname}')
        command chafa -f kitty --passthrough tmux $argv
    else
        command chafa $argv
    end
end

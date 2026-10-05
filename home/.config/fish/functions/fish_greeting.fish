# Runs once per interactive session (every new terminal, tmux pane or ssh
# login), never for `fish -c` or scripts. Both tools come from nix/flake.nix;
# on a machine whose profile predates them fish prints "Unknown command",
# which means: run dotup. Any length on purpose: `-s` (short only, <160
# chars) left out the longer quotes, at the cost of the odd screenful.
#
# -c heads the quote with its database, so you know where to find more:
#   (pratchett)        -> `fortune pratchett` for another
#   %
#   <quote>
# cowsay -n keeps the quote's own line breaks (fortunes are pre-wrapped,
# widest line 80); without it cowsay rewraps to 40 columns and mangles
# poems and chat logs.
function fish_greeting
    fortune -c | cowsay -n
end

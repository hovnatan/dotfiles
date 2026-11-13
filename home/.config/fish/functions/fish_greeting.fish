# Runs once per interactive session (every new terminal, tmux pane or ssh
# login), never for `fish -c` or scripts. Both tools come from nix/flake.nix;
# on a machine whose profile predates them fish prints "Unknown command",
# which means: run dotup. Any length on purpose: `-s` (short only, <160
# chars) left out the longer quotes, at the cost of the odd screenful.
#
# -c heads the quote with its database, so you know where to find more:
#   (pratchett)        -> `fortune pratchett` for another
#   %                  dropped: in the bubble it read as a stray prompt
#   <quote>
# A line that is "%" alone is never part of a quote: it is the separator
# between quotes in fortune's own files.
# cowsay -n keeps the quote's own line breaks (fortunes are pre-wrapped,
# widest line 80); without it cowsay rewraps to 40 columns and mangles
# poems and chat logs.
function fish_greeting
    fortune -c | string match -v -- % | cowsay -n
end

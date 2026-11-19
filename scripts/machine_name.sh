#!/usr/bin/env bash
# machine_name.sh -- print this machine's name, the one its prompt, its
# titles, its claude sessions and its phone notifications show:
#
#   claude session   mbp/eye-breaks   (<machine>/<tmux session>)
#   notification     CC: mbp/eye-breaks
#   terminal title   (mbp) [eye-breaks] in tmux, (mbp) fish: ~/x outside it
#
# The rule, in order:
#
#   ~/.config/dotfiles/machine-name there   -> its one line          "mbp"
#   absent  -> the host name up to its first dot   "vm.internal" -> "vm"
#
# The file is for a machine whose host name says nothing (a Mac's own is
# "Mac") or is long. It is a per-machine file (CONTEXT.md): kept in the
# private repo, under machines/<name>/home/.config/dotfiles/, since this repo
# is public and names no machine.
#
# tmux asks this script once, as its config loads (@machine, for the title
# and the bar). Three more read the same file by the same rule, each with
# its own builtins because it runs at every prompt or redraw: fish
# (machine_name.fish), zsh's title (home/.zshrc.shared) and nvim's
# (core/options.lua). They show what they find; this script is the one that
# checks it.
set -euo pipefail

file="$HOME/.config/dotfiles/machine-name"

if [ -e "$file" ]; then
  # One word: it becomes the first half of "<machine>/<session>", typed into
  # a shell as an argument and sent as an HTTP header.
  name=$(<"$file")
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "machine_name.sh: $file holds '$name', not one word of letters, digits, '.', '_' or '-'; fix it, or remove it to go by the host name" >&2
    exit 1
  }
else
  name=$(hostname)
  name=${name%%.*}
  [ -n "$name" ] || {
    echo "machine_name.sh: hostname prints nothing; name this machine in $file" >&2
    exit 1
  }
fi

printf '%s\n' "$name"

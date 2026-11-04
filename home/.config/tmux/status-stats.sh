#!/usr/bin/env bash
# status-stats.sh -- CPU and memory use for the tmux status bar
# (home/.tmux.conf, status-right), labelled:
#
#   tmux-mem-cpu-load -a 0 -m 2 -g 0 -i 2   ->  "74.94%  18.5%"   (memory, CPU)
#   this script                             ->  "cpu 18.5% mem 74.9%"
#
# The tool prints memory first and has no labels, and its order is fixed;
# this reorders and labels it. A script rather than an awk line in the
# config: status-right goes through strftime (a printf "%s" would become the
# epoch time) and two layers of quoting before a shell sees it.
#
# tmux runs it in the background every status-interval and draws what it
# prints, so a failure is printed, not logged: it shows in the bar where the
# numbers would be. By full path: the tmux server's systemd unit may not
# have the Nix profile on PATH. -i 2 is the CPU sample, 2 s. Nothing is
# written to an event log: it acts on nothing, and runs every 15 s.
set -u

tool="$HOME/.nix-profile/bin/tmux-mem-cpu-load"
if [ ! -x "$tool" ]; then
  echo "no $tool (nix/flake.nix; dotup installs it)"
  exit 1
fi
# 3.8.3 ends its line with a NUL byte, which bash would drop with a warning
set -o pipefail
if ! out=$("$tool" -a 0 -m 2 -g 0 -i 2 2>&1 | tr -d '\000'); then
  echo "tmux-mem-cpu-load failed: $out"
  exit 1
fi

# "74.94%  18.5%" -> mem=74.94% cpu=18.5%; anything else is a format change
read -r mem cpu rest <<<"$out"
case "$mem $cpu ${rest:-}" in
  *%\ *%\ ) printf 'cpu %s mem %.1f%%\n' "$cpu" "${mem%\%}" ;;
  *)
    echo "tmux-mem-cpu-load printed '$out', not '<mem>% <cpu>%'"
    exit 1
    ;;
esac

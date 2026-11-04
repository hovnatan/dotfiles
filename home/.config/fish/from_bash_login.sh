# shellcheck shell=bash
# Hand a person's terminal login over to fish, and nothing else. The passwd
# shell stays bash: Claude Code's Bash tool, `ssh host cmd` and systemd units
# read this file too, and an unconditional fish here blocks all of them on a
# prompt nobody answers.
#   ssh vm                          interactive, tty          -> fish
#   bash -lc '...' (the unit)       -c, not interactive       -> stays bash
#   Bash tool, ssh vm cmd           not interactive / no tty  -> stays bash
#   `bash` typed inside fish        parent is fish            -> stays bash
# If fish is missing, exec fails loudly and an interactive bash carries on.
if [ -n "$BASH_VERSION" ] && [ -z "$BASH_EXECUTION_STRING" ] && [ -t 0 ]; then
  case $- in
    *i*)
      if [ "$(ps -o comm= -p "$PPID")" != fish ]; then
        exec fish --login
      fi
      ;;
  esac
fi
